#lang curly-fn racket

(require plot
         (only-in racket/hash hash-union!)
         (only-in racket/file write-to-file))

;;;;;;;;;;;;;;;;;
;; EXPRESSIONS ;;
;;;;;;;;;;;;;;;;;

#|
This is a script for traversing a file system and collecting various distributional data about its structure.
These specific data are collected because it is what is found in Figure 2 of Agrawal [1].
The name "Expressions" was chosen for continuity with Agrawal's *Impressions* and *Compressions*,
and also because I'm using Racket instead of Python and the former consists of s-expressions.

Some handy commands:
* (write-stats! (expressions*)) to write stats about everything in init-dirs to stats.rkt
* (write-stats! (expressions "raw.rkt")) to write the raw stats instead of cooked stats
* (plot-stats (read-stats)) to plot stats read from stats.rkt
* (plot-stats (read-stats "original.rkt") (read-stats "generated.rkt")) to plot stats comparisons

[1] Nitin Agrawal, Andrea C. Arpaci-Dusseau, Remzi H. Arpaci-Dusseau.
    "Generating Realistic Impressions for File-System Benchmarking" (2009).
    https://doi.org/10.1145/1629080.1629086.
|#

;; STATS ;;

#|
The raw stats from expressions contain the distributions for various filesystem properties:
* dir-depths: Namespace depth ↦ number of directories at that depth
  N.B. Directories in root have depth 0, and root is not counted
* subdir-counts: Number of subdirectories ↦ number of directories with that many subdirectories
* file-counts: Number of files ↦ number of directories with that many files
* file-sizes: File size bins ↦ number of files with that size in bytes
  Specifically, a file of size N bytes would go in the ⌊log₂(N)⌋th bin; files with size 0B are ignored
* file-bytes: File size bins ↦ total number of bytes in files in that bin; bins are as above
* file-depths: Namespace depth ↦ number of files at that depth
  N.B. Files in root have depth 0
* byte-depths: Namespace depth ↦ total number of bytes in files at that depth

The cooked stats from expressions* contain mappings to percentages instead of numbers, except for:
* subdir-counts: Number of subdirectories ↦ percentage of directories with that many subdirectories or fewer
* byte-depths: Namespace depth ↦ bins of average bytes per file; bins are as above
|#

(struct stats (dir-depths subdir-counts file-counts file-sizes file-bytes file-depths byte-depths) #:transparent)
(define (empty-stats)
  (stats (make-hash) (make-hash) (make-hash) (make-hash) (make-hash) (make-hash) (make-hash)))

;; EXPRESSIONS ;;

;; init-dirs : (listof path?)
;; The initial default directories to analyze, treating / as depth 0
;; N.B. We exclude directories containing irrelevant, impermanent, or linked data, specifically:
;;    * /lost+found (recovered files)
;;    * /dev, /media, and /mnt (devices and mount points)
;;    * /proc and /sys (process and kernel files)
;;    * /tmp, /var, and /run (temporary, variable, and runtime files)
;;    * /bin and /sbin; /lib and /lib64 (linked to /usr/bin; /usr/lib)
(define init-dirs
  (map #{list % 1}
       '("/boot" "/etc" "/home" "/opt" "/root" "/srv" "/usr")))

;; expressions : [path? #f] -> stats?
;; Starting from the given path as depth 0, returns filesystem structure stats;
;; links are ignored so that we don't count files twice, and empty files are also ignored
(define (expressions [path #f])
  (let loop ([dirs (or (and path `((,path ,0))) init-dirs)]
             [stats (empty-stats)])
    (match dirs
      ['() stats]
      [`((,dir ,depth) ,dirs ...)
       (for/fold ([dirs dirs]
                  [subdirs 0]
                  [files 0]
                  #:result
                  (begin (hash-update! (stats-subdir-counts stats) subdirs add1 0)
                         (hash-update! (stats-file-counts stats) files add1 0)     
                         (loop dirs stats)))
                 ([curr (map #{build-path dir %} (directory-list dir))])
         (match (file-or-directory-type curr)
           ['file
            (define size (file-size curr))
            (unless (or (zero? size) (path-has-extension? curr #".iso"))
              (define lg-size (exact-floor (log size 2)))
              (hash-update! (stats-file-depths stats) depth add1 0)
              (hash-update! (stats-file-sizes stats) lg-size add1 0)
              (hash-update! (stats-file-bytes stats) lg-size #{+ size %} 0)
              (hash-update! (stats-byte-depths stats) depth #{+ size %} 0))
            (values dirs subdirs (add1 files))]
           ['directory
            (hash-update! (stats-dir-depths stats) depth add1 0)
            (values (cons `(,curr ,(add1 depth)) dirs) (add1 subdirs) files)]
           [else (values dirs subdirs files)]))])))

;; expressions* : [path? #f] -> stats?
;; Same as expressions, but returns cooked stats instead of raw stats
(define (expressions* [path #f])
  (let ([stats (expressions path)])
    ;; Bind distribution hashes for convenience
    (define dir-depths (stats-dir-depths stats))
    (define subdir-counts (stats-subdir-counts stats))
    (define file-counts (stats-file-counts stats))
    (define file-sizes (stats-file-sizes stats))
    (define file-bytes (stats-file-bytes stats))
    (define file-depths (stats-file-depths stats))
    (define byte-depths (stats-byte-depths stats))
    ;; Calculate totals to divide by
    (define total-dirs (apply + (hash-values dir-depths)))
    (define total-files (apply + (hash-values file-depths)))
    (define total-bytes (apply + (hash-values byte-depths)))
    ;; Cook raw distributions
    (cumulativize! subdir-counts)
    (hash-union! byte-depths file-depths #:combine #{log (/ %1 %2) 2})
    (for ([key (hash-keys dir-depths)])
      (hash-update! dir-depths key #{/ % total-dirs}))
    (for ([key (hash-keys subdir-counts)])
      (hash-update! subdir-counts key #{/ % total-dirs}))
    (for ([key (hash-keys file-counts)])
      (hash-update! file-counts key #{/ % total-dirs}))
    (for ([key (hash-keys file-sizes)])
      (hash-update! file-sizes key #{/ % total-files})
      (hash-update! file-bytes key #{/ % total-bytes}))
    (for ([key (hash-keys file-depths)])
      (hash-update! file-depths key #{/ % total-files}))
    stats))

;; VISUALIZATIONS ;;

;; plot-stats : stats? -> (listof plot?)
;; Plots the given stats as a list of distributions
(define (plot-stats stats)
  (define dir-depths (sequentialize (stats-dir-depths stats)))
  (define subdir-counts (sequentialize (stats-subdir-counts stats)))
  (define file-counts (sequentialize (stats-file-counts stats)))
  (define file-sizes (sequentialize (stats-file-sizes stats)))
  (define file-bytes (sequentialize (stats-file-bytes stats)))
  (define file-depths (sequentialize (stats-file-depths stats)))
  (define byte-depths (sequentialize (stats-byte-depths stats)))
  (list (plot (list (points dir-depths)
                    (lines dir-depths))
              #:title "Directories by Namespace Depth" #:x-min 0 #:y-min 0
              #:x-label "Namespace depth" #:y-label "% of directories")
        (plot (list (points subdir-counts)
                    (lines subdir-counts))
              #:title "Directories by Subdirectory Count" #:x-min 0 #:y-min 0
              #:x-label "Subdirectory count" #:y-label "Cumulative % of directories")
        (plot (list (points file-counts)
                    (lines file-counts))
              #:title "Directories by File Count" #:x-min 0 #:y-min 0
              #:x-label "File count" #:y-label "% of directories")
        (plot (list (points file-sizes)
                    (lines file-sizes))
              #:title "Files by File Size" #:x-min 0 #:y-min 0
              #:x-label "File size (log₂(bytes))" #:y-label "% of files")
        (plot (list (points file-bytes)
                    (lines file-bytes))
              #:title "Bytes by File Size" #:x-min 0 #:y-min 0
              #:x-label "File size (log₂(bytes))" #:y-label "% of bytes")
        (plot (list (points file-depths)
                    (lines file-depths))
              #:title "Files by Namespace Depth" #:x-min 0 #:y-min 0
              #:x-label "Namespace depth" #:y-label "% of files")
        (plot (list (points byte-depths)
                    (lines byte-depths))
              #:title "Average Bytes per File by Namespace Depth" #:x-min 0 #:y-min 0
              #:x-label "Namespace depth" #:y-label "Average size (log₂(bytes)/file)")))

;; plot-stats : stats? stats? -> (listof plot?)
;; Plots the given pair of stats as a list of distributions,
;; where each plot compares the corresponding distributions for both stats
(define (plot-stats-compare stats-original stats-generated)
  ;; Original distributions
  (define dir-depths-original (sequentialize (stats-dir-depths stats-original)))
  (define subdir-counts-original (sequentialize (stats-subdir-counts stats-original)))
  (define file-counts-original (sequentialize (stats-file-counts stats-original)))
  (define file-sizes-original (sequentialize (stats-file-sizes stats-original)))
  (define file-bytes-original (sequentialize (stats-file-bytes stats-original)))
  (define file-depths-original (sequentialize (stats-file-depths stats-original)))
  (define byte-depths-original (sequentialize (stats-byte-depths stats-original)))
  ;; Generated distributions
  (define dir-depths-generated (sequentialize (stats-dir-depths stats-generated)))
  (define subdir-counts-generated (sequentialize (stats-subdir-counts stats-generated)))
  (define file-counts-generated (sequentialize (stats-file-counts stats-generated)))
  (define file-sizes-generated (sequentialize (stats-file-sizes stats-generated)))
  (define file-bytes-generated (sequentialize (stats-file-bytes stats-generated)))
  (define file-depths-generated (sequentialize (stats-file-depths stats-generated)))
  (define byte-depths-generated (sequentialize (stats-byte-depths stats-generated)))
  ;; Plots to draw
  (list (plot (list (points dir-depths-original #:sym 'circle)
                    (lines dir-depths-original #:color 'red)
                    (points dir-depths-generated #:sym 'square)
                    (lines dir-depths-generated #:color 'blue))
              #:title "Directories by Namespace Depth" #:x-min 0 #:y-min 0
              #:x-label "Namespace depth" #:y-label "% of directories")
        (plot (list (points subdir-counts-original #:sym 'circle)
                    (lines subdir-counts-original #:color 'red)
                    (points subdir-counts-generated #:sym 'square)
                    (lines subdir-counts-generated #:color 'blue))
              #:title "Directories by Subdirectory Count" #:x-min 0 #:y-min 0
              #:x-label "Subdirectory count" #:y-label "Cumulative % of directories")
        (plot (list (points file-counts-original #:sym 'circle)
                    (lines file-counts-original #:color 'red)
                    (points file-counts-generated #:sym 'square)
                    (lines file-counts-generated #:color 'blue))
              #:title "Directories by File Count" #:x-min 0 #:y-min 0
              #:x-label "File count" #:y-label "% of directories")
        (plot (list (points file-sizes-original #:sym 'circle)
                    (lines file-sizes-original #:color 'red)
                    (points file-sizes-generated #:sym 'square)
                    (lines file-sizes-generated #:color 'blue))
              #:title "Files by File Size" #:x-min 0 #:y-min 0
              #:x-label "File size (log₂(bytes))" #:y-label "% of files")
        (plot (list (points file-bytes-original #:sym 'circle)
                    (lines file-bytes-original #:color 'red)
                    (points file-bytes-generated #:sym 'square)
                    (lines file-bytes-generated #:color 'blue))
              #:title "Bytes by File Size" #:x-min 0 #:y-min 0
              #:x-label "File size (log₂(bytes))" #:y-label "% of bytes")
        (plot (list (points file-depths-original #:sym 'circle)
                    (lines file-depths-original #:color 'red)
                    (points file-depths-generated #:sym 'square)
                    (lines file-depths-generated #:color 'blue))
              #:title "Files by Namespace Depth" #:x-min 0 #:y-min 0
              #:x-label "Namespace depth" #:y-label "% of files")
        (plot (list (points byte-depths-original #:sym 'circle)
                    (lines byte-depths-original #:color 'red)
                    (points byte-depths-generated #:sym 'square)
                    (lines byte-depths-generated #:color 'blue))
              #:title "Average Bytes per File by Namespace Depth" #:x-min 0 #:y-min 0
              #:x-label "Namespace depth" #:y-label "Average size (log₂(bytes)/file)")))

;; HELPERS ;;

;; cumulativize! : (hashof number? number?) -> (hashof number? number?)
;; Turn a distribution into a cumulative distribution
(define (cumulativize! distr)
  (for/fold ([cumul 0])
            ([key (sort (hash-keys distr) <)])
    (hash-update! distr key #{+ % cumul})
    (hash-ref distr key)))

;; sequentialize : (hashof number? number?) -> (listof (list number? number?))
;; Turns a hash distribution into a sequence of data points (i.e. list of 2 dimensions)
(define (sequentialize distr)
  (hash-map distr list #t))

;; write-stats! : stats? [path? (build-path (current-directory) "stats.rkt")] -> void?
;; Writes a stats object to file
(define (write-stats! stats [path (build-path (current-directory) "stats.rkt")])
  (with-output-to-file path
    (λ () (print stats))
    #:exists 'replace))

;; read-stats : [path? (build-path (current-directory) "stats.rkt")] -> stats?
;; Reads a stats object from file
(define (read-stats [path (build-path (current-directory) "stats.rkt")])
  (with-input-from-file path
    (λ () (eval (read)))))

;; stats->csv : stats? -> void?
;; Writes a stats object to several fixed CSV files
(define (stats->csv! stats)
  (define (distr->csv! distr path)
    (with-output-to-file path
      (λ () 
        (hash-for-each distr #{displayln (format "~a,~a" (exact->inexact %1) (exact->inexact %2))} #t))
      #:exists 'replace))
  (distr->csv! (stats-dir-depths stats) "dir-depths.csv")
  (distr->csv! (stats-subdir-counts stats) "subdir-counts.csv")
  (distr->csv! (stats-file-counts stats) "file-counts.csv")
  (distr->csv! (stats-file-sizes stats) "file-sizes.csv")
  (distr->csv! (stats-file-bytes stats) "file-bytes.csv")
  (distr->csv! (stats-file-depths stats) "file-depths.csv")
  (distr->csv! (stats-byte-depths stats) "byte-depths.csv"))

;; CLI ;;

#;
(let loop ([args (vector->list (current-command-line-arguments))]
           [root #f]
           [out #f]
           [raw #f])
  (if (empty? args)
      (let ([stats (let ([express (if raw expressions expressions*)])
                     (if root (express root) (express)))])
        (if out (write-stats stats out) (write-stats stats)))
      (match (first args)
        ["--root" (if root
                      (error "Duplicate flag --root.")
                      (loop (cddr args) (second args) out raw))]
        ["--out" (if out
                     (error "Duplicate flag --out.")
                     (loop (cddr args) root (second args) raw))]
        ["--raw" (loop (cdr args) root out #t)])))
