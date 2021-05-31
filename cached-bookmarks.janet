#!/usr/bin/env janet
(import sh)

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
          update-cache |(let [bookmarks (format-bookmarks
                                          (sh/$< buku --nostdin -p -f 5))]
                          (when (not (os/stat cache-dir))
                            (os/mkdir cache-dir))
                          (if-with [f (file/open cache :w)]
                            (file/write f bookmarks)
                            (error (string "Cannot write to " cache)))
                          bookmarks)]
      (if-let [cache-modified (get (os/stat cache) :modified)]
        (if (< cache-modified db-modified)
          (update-cache)
          (if-with [f (file/open cache :r)]
            (file/read f :all)
            (error (string "Cannot read " cache))))
        (update-cache)))))

(defn main
  [&]
  (print (get-cached-bookmarks)))
