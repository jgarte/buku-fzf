#!/usr/bin/env janet
(import sh)
(import argparse)

(def- description
  ``
  Choose buku bookmarks on fzf. Open them in web browsers of your choice.
  To select multiple bookmarks, press tab or shift+tab.
  buku-fzf does exact match on fzf. To do fuzzy match, use a search term
  with a prefixed single quote such as 'search-term instead of search-term.

  If the value of --browser or --browser-tag contains
  spaces, surround the values of the options in double quotes.
  For example, buku-fzf -b "firefox --new-tab"

  --browser-tag associates a certain buku bookmark tag with a certain
  browser command. --browser-tag can be specified multiple times in order
  to define multiple tags associated with different web browsers.

  For example,
  if you execute buku-fzf -b firefox -t "torbrowser,torbrowser --allow-remote",
  any bookmark with torbrowser tag is opened with
  torbrowser --allow-remote bookmark-url

  Note that browser commands currently don't support quotes for simplicity.
  Thus, buku-fzf -b "firefox --option1 \"abc abc\"" doesn't work.

  Example commands:
  buku-fzf -b "firefox --new-tab"
  buku-fzf -b firefox -t "torbrowser,torbrowser --allow-remote"
  buku-fzf -b firefox -t chromium,chromium -t brave,brave-bin
  buku-fzf -b firefox -t chromium,chromium -t "brave browser,brave-bin"
  ``)

(defn- format-bookmarks
  [raw-bookmarks]
  (if-let [parsed-bookmarks (peg/match
                              '{:column (some (if-not (+ "\t" "\n") 1))
                                :main (some (group (* ':column "\t"
                                                      ':column "\t"
                                                      ':column "\n")))}
                              raw-bookmarks)]
    (string/join (map |(let [[index title tags] $]
                         (string/format "%s\t%s\t(%s)"
                                        index title tags))
                      parsed-bookmarks)
                 "\n")
    (error "Failed to parse bookmarks.")))

(defn- get-cached-bookmarks
  []
  (when-let [home (os/getenv "HOME")
             db-modified
             (if-let [xdg-data-home (os/getenv "XDG_DATA_HOME")
                      db (os/stat (string xdg-data-home "/buku/bookmarks.db"))]
               (db :modified)
               (get (os/stat (string home "/.local/share/buku/bookmarks.db"))
                    :modified))]
    (let [cache-dir (string home "/.cache")
          cache (string cache-dir "/buku-fzf")
          update-cache |(let [bookmarks (format-bookmarks (sh/$< buku -p -f 5))]
                          (when (not (os/stat cache-dir))
                            (os/mkdir cache-dir))
                          (if-with [f (file/open cache :w)]
                            (file/write f bookmarks)
                            (error (string "Cannot write to " cache)))
                          bookmarks)]
      (if-let [cache-modified (get (os/stat cache) :modified)]
        (if (<= cache-modified db-modified)
          (update-cache)
          (if-with [f (file/open cache :r)]
            (file/read f :all)
            (error (string "Cannot read " cache))))
        (update-cache)))))

(defn- parse-opts
  []
  (when-let [{"browser" browser "browser-tag" browser-tags}
             (argparse/argparse
               description
               "browser" {:kind :option
                          :required true
                          :help "Format: \"browser command\""
                          :short "b"}
               "browser-tag" {:kind :accumulate
                              :help
                              "Format: \"browser tag,browser command\""
                              :short "t"})]
    (let [tag-word '(some (if-not (+ "," " ") 1))
          tag ~(* ,tag-word (any (* " " ,tag-word)))
          arg '(some (if-not " " 1))
          cmd ~(* ',arg (any (* (some " ") ',arg)))]
      {"browser" (peg/match cmd browser)
       "browser-tags"
       (when browser-tags
         (->> browser-tags
              (map |(if-let [browser-tag (peg/match ~(* ',tag "," (group ,cmd))
                                                    $)]
                      browser-tag
                      (error (string/format
                               "'%s' is an invalid value for --browser-tag."
                               $))))
              (reduce (fn [acc [k v]]
                        (put acc k v))
                      @{})))})))

(defn main
  [& args]
  (when-let
    [{"browser" browser "browser-tags" browser-tags} (parse-opts)
     bookmarks (get-cached-bookmarks)
     indices (try
               (->> (sh/$< fzf -e -m +s --layout=reverse < ,bookmarks)
                    (peg/match '(some (* '(some :d+)
                                         (some (if-not "\n" 1))
                                         "\n"))))
               ([_]))]
    (let [urls-with-tags
          (->> (sh/$< buku -p ;indices -f 20)
               (peg/match '{:url (some (if-not "\t" 1))
                            :tag (some (if-not (+ "," "\n") 1))
                            :tags (group (* ':tag
                                            (any (* "," ':tag))))
                            :main (some (group (* ':url "\t"
                                                  :tags "\n")))}))
          devnull (os/open "/dev/null" :w)
          openUrl (fn [browser url]
                    (os/execute (reduce |(array/push $0 $1)
                                        @["nohup" "setsid" "-f"]
                                        (array/push (array ;browser) url))
                                :p
                                {:out devnull :err devnull}))]
      (loop [[url tags] :in urls-with-tags]
        (if browser-tags
          (if-let [tagged-browser (some |(get browser-tags $) tags)]
            (openUrl tagged-browser url)
            (openUrl browser url))
          (openUrl browser url))))))
