(declare-project
  :name "buku-fzf"
  :description
   "Choose buku bookmarks on fzf. Open them in browsers of your choice."
  :dependencies ["https://github.com/janet-lang/argparse"
                 "https://github.com/andrewchambers/janet-sh"])

(declare-executable
  :name "buku-fzf"
  :entry "main.janet"
  :install true)

(declare-executable
  :name "buku-fzf-cached-bookmarks"
  :entry "cached-bookmarks.janet"
  :install true)
