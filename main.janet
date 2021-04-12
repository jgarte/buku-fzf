#!/usr/bin/env janet
(import sh)
(import argparse)

(def- description
  ``
  Choose `buku` bookmarks in fzf. Open them in web browser.

  If the value of browser command in --browser or --browser-tag contains
  spaces, surround the values of the options in double quotes.
  For example, buku-fzf -b "firefox --new-tab"

  --browser-tag associates a certain buku bookmark tag with a certain
  browser command. --browser-tag can be specified multiple times in order
  to define multiple tags associated with different web browsers.

  Note that browser commands currently don't support quotes for simplicity.
  Thus, buku-fzf -b "firefox --option1 \"abc abc\"" doesn't work.

  Example commands:
  buku-fzf -b "firefox --new-tab"
  buku-fzf -b firefox -t "torbrowser,torbrowser --allow-remote"
  buku-fzf -b firefox -t chromium,chormium -t brave,brave-bin
  ``)

(defn- get-bookmarks
  []
  (->> (peg/match '{:column
                    (some (if-not (+ "\t" "\n") 1))
                    :entry (group (* ':column "\t"
                                     ':column "\t"
                                     ':column "\n"))
                    :main (some :entry)}
                  (sh/$< buku -p -f 5))
       (map |(let [[index title tags] $]
               (string/format "%s\t%s\t(%s)"
                              index title tags)))
       (|(string/join $ "\n"))))

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
                              "Format: \"browser-tag,browser command\""
                              :short "t"})]
    {"browser" (peg/match '(* '(some (if-not " " 1))
                              (any (* (some " ")
                                      '(some (if-not " " 1)))))
                          browser)
     "browser-tags"
     (if (not (nil? browser-tags))
       (let [browser-tag-peg
             '(* '(some (if-not "," 1))
                 ","
                 (group (* '(some (if-not (+ "," " ") 1))
                           (any (* (some " ")
                                   '(some (if-not (+ "," " ") 1)))))))]
         (->> browser-tags
              (map |(if-let [browser-tag (peg/match browser-tag-peg $)]
                      browser-tag
                      (do
                        (print (string/format
                                 "'%s' is an invalid value for --browser-tag."
                                 $))
                        (os/exit 1))))
              (reduce (fn [acc [k v]]
                        (put acc k v))
                      @{})))
       {})}))

(defn main
  [& args]
  (when-let [{"browser" browser "browser-tags" browser-tags} (parse-opts)
             indices
             (try
               (peg/match
                 '(some (* '(some :d+)
                           (some (if-not "\n" 1))
                           "\n"))
                 (sh/$< fzf -e -m +s --layout=reverse < ,(get-bookmarks)))
               ([_]))]
    (let [devnull (os/open "/dev/null" :w)
          urls-with-tags (peg/match
                           '{:url (some (if-not "\t" 1))
                             :tag (some (if-not (+ "," "\n") 1))
                             :tags (group (* ':tag
                                             (any (* "," ':tag))))
                             :main (some (group (* ':url "\t" :tags "\n")))}
                           (sh/$< buku -p ;indices -f 20))
          openUrl (fn [browser url]
                    (os/execute (reduce |(array/push $0 $1)
                                        @["setsid" "-f"]
                                        (array/push (array ;browser) url))
                                :p
                                {:out devnull :err devnull}))]
      (loop [[url tags] :in urls-with-tags]
        (if-let [tagged-browser (some |(get browser-tags $) tags)]
          (openUrl tagged-browser url)
          (openUrl browser url))))))
