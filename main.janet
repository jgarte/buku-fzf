#!/usr/bin/env janet
(import sh)
(import argparse)

(def- description
  ``
  Usage: buku-fzf [options] [bookmark-number1 bookmark-number2 ...]
  Choose buku bookmarks on fzf. Open them in web browsers of your choice.

  If buku-fzf is given one or more numbers, the numbers are interpreted as
  buku bookmarks to open, and bookmarks are opened without launching fzf.

  To select multiple bookmarks in fzf, press tab or shift+tab.
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

(defn- parse-opts
  []
  (when-let [{"browser" browser "browser-tag" browser-tags "query" query
              "bind" bind :default bookmarks}
             (argparse/argparse
               description
               "browser" {:kind :option
                          :required true
                          :help "Format: \"browser command\""
                          :short "b"}
               "browser-tag" {:kind :accumulate
                              :help
                              "Format: \"browser tag,browser command\""
                              :short "t"}
               "query" {:kind :option
                        :help "This option is passed to fzf"
                        :short "q"}
               "bind" {:kind :accumulate
                       :help "This option is passed to fzf"
                       :short "B"}
               :default {:kind :accumulate})]
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
                      @{})))
       "query" query
       "bind" bind
       "bookmarks" bookmarks})))

(defn main
  [& args]
  (when-let
    [{"browser" browser "browser-tags" browser-tags "query" query
      "bookmarks" bookmarks "bind" bind} (parse-opts)
     indices (if bookmarks
               bookmarks
               (try
                 (->> (sh/$< fzf -e -m +s --layout=reverse
                             ;(if query
                                [(string "--query=" query)]
                                [])
                             ;(if bind
                                (map |(string "--bind=" $) bind)
                                [])
                             < (sh/$< buku-fzf-cached-bookmarks))
                      (peg/match '(some (* '(some :d+)
                                           (some (if-not "\n" 1))
                                           "\n"))))
                 ([_])))]
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
