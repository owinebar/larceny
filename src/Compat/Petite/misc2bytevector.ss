; Copyright 1998 Lars T Hansen.
;
; $Id$
;
; Convert various data into bytevector representation.
; The bytevector header is not included in the returned bytevector.
;
; These support routines run under Chez Scheme and other implementations
; without native support for byte vectors.

(if (not (eq? (nbuild-parameter 'target-endianness) 'big))
    (error "misc2bytevector.ss is only for big-endian targets."))

; Generic.

(define (string->bytevector s)
  (list->bytevector (map char->integer (string->list s))))

; Generic.

(define (symbol->bytevector s)
  (string->bytevector (symbol->string s)))

; Bignums are bytevector-like with the sign in the high byte of
; the first word (0 for 0 or positive, 1 for negative), a digit
; count in the low 24 bits (three bytes) and then base-2^32 digits
; in the next words with the least significant word first.
;
;       big end                  little end
;       +------------------------+--------+
;       |       length           | header |
;       +------------------------+--------+
;       | sign   |          digitcount    |
;       +---------------------------------+
;       |              lsd                |
;       +---------------------------------+
;       ...

(define (bignum->bytevector b)

  (define two^32 (expt 2 32))

  (define (flatten x)
    (apply append x))

  ; returned list has length congruent to 0 mod 4.

  (define (divide b l)
    (if (< b two^32)
        (flatten (reverse (cons (split-int b) l)))
        (divide (quotient b two^32)
                (cons (split-int (remainder b two^32)) l))))

  (let* ((sign   (if (negative? b) 1 0))
         (b      (abs b))
         (digits (divide b '()))
         (len    (quotient (length digits) 4)))
    (list->bytevector
     (append (split-int (+ len (fxlsh sign 24))) digits))))


; IEEE specific, and specific to Chez Scheme.
;
; Flonums (IEEE double) are bytevector-like. The first word is unused. The two
; next words contain the double:
;
;       +------------------------+--------+
;       |      length            | header |
;       +------------------------+--------+
;       |      unused                     |
;       +---------------------------------+
;       |      IEEE double precision      |
;       |                                 |
;       +---------------------------------+
;
; Compnums are similar:
;
;       +------------------------+--------+
;       |      length            | header |
;       +------------------------+--------+
;       |      unused                     |
;       +---------------------------------+
;       |      (real part)                |
;       |      IEEE double precision      |
;       +---------------------------------+
;       |      (imaginary part)           |
;       |      IEEE double precision      |
;       +---------------------------------+
;
; An IEEE number, in turn, is represented as follows (64 bits)
;
;       +-+----------+--------------------+
;       |s| exponent |                    |    low word
;       +-+----------+--------------------+
;       |                                 |    high word
;       +---------------------------------+
;
; where the sign (s) is one bit, the exponent is 11 bits, and the fraction is
; the remaining 52 bits. The exponent is biased with 1023, and the fraction
; is normalized with a hidden leading '1' bit.
;
; Under Chez Scheme, there are peculiar global variables to represent NaNs and
; Infs: +inf.0, -inf.0, +nan.0, and -nan.0. These "numbers" have specific
; representations in the IEEE format, and are special-cased below. For NaNs,
; the sign is to be ignored (in fact, +nan.0 and -nan.0 both evaluate to
; +nan.0), and we always give these numbers a 0 sign bit.
;
; In Chez Scheme v4, all NaNs are equal?.
;
; There is no provision for denormals here.

(define (flonum->bytevector f)
  (list->bytevector (append '(0 0 0 0) (flonum-bits f))))

(define (compnum->bytevector c)
  (let ((f1 (flonum-bits (real-part c)))
        (f2 (flonum-bits (imag-part c))))
    (list->bytevector (append '(0 0 0 0) f1 f2))))

; Return a list of byte values representing an IEEE double precision number.
; Big endian always.

(define flonum-bits
  (let ((two^52 (expt 2 52))
        (two^48 (expt 2 48))
        (two^40 (expt 2 40))
        (two^32 (expt 2 32))
        (two^24 (expt 2 24))
        (two^16 (expt 2 16)))
    (lambda (f)
      (cond ((= f +inf.0)
             '(#x7F #xF0 0 0 0 0 0 0))
            ((= f -inf.0)
             '(#xFF #xF0 0 0 0 0 0 0))
            ((not (= f f))
             '(#x7F #xFF #xFF #xFF #xFF #xFF #xFF #xFF))
            ((= f 0.0)
             (if (negative? (vector-ref (decode-float f) 2))
                 '(#x80 0 0 0 0 0 0 0)
                 '(0 0 0 0 0 0 0 0)))
            (else
             (let* ((d (decode-float f))
                    (m (- (vector-ref d 0) two^52))
                    (e (+ (vector-ref d 1) 52 1023))
                    (s (if (negative? (vector-ref d 2)) 1 0)))
               (list (fxlogor (fxsll s 7)
                              (fxlogand (fxsrl e 4) 127))
                     (fxlogor (fxsll (fxlogand e 15) 4)
                              (fxlogand (quotient m two^48) 15))
                     (remainder (quotient m two^40) 256)
                     (remainder (quotient m two^32) 256)
                     (remainder (quotient m two^24) 256)
                     (remainder (quotient m two^16) 256)
                     (remainder (quotient m 256) 256)
                     (remainder m 256))))))))

; utility

(define (split-int b)
  (define two^32 (expt 2 32))
  (define two^24 (expt 2 24))
  (define two^16 (expt 2 16))
  (define two^8  (expt 2 8))

  (list (quotient b two^24)
        (quotient (remainder b two^24) two^16)
        (quotient (remainder b two^16) two^8)
        (remainder b two^8)))

; eof
