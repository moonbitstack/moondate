/// The two dated text formats that are not RFC 3339: HTTP and ASN.1.
///
/// Every protocol invents its own way to spell a date, and then keeps the old
/// spellings working forever. These two families are the ones you meet while
/// speaking to a server or reading a certificate.
///
///     moon run src/examples/wire

///|
/// Parse an ASN.1 time and report either the reading or the refusal, so the
/// table below stays one line per case.
fn asn1_error(text : String) -> String {
  try {
    let moment = @moondate.asn1(text)
    "accepted as " + moment.to_string()
  } catch {
    err => err.to_string()
  }
}

///|
fn http_error(text : String) -> String {
  try {
    let moment = @moondate.http(text)
    "accepted as " + moment.to_string()
  } catch {
    err => err.to_string()
  }
}

///|
fn main raise {
  // ---- HTTP ---------------------------------------------------------------
  //
  // RFC 9110 asks a recipient to accept three formats. The first is the one to
  // send; the other two are the ones you must still read.

  let imf = @moondate.http("Sun, 06 Nov 1994 08:49:37 GMT") // the one to send
  let rfc850 = @moondate.http("Sunday, 06-Nov-94 08:49:37 GMT") // obsolete
  let asctime = @moondate.http("Sun Nov  6 08:49:37 1994") // obsolete

  println(imf)
  println(rfc850)
  println(asctime)
  println(
    "all three are the same instant: " +
    (imf.epoch() == asctime.epoch()).to_string(),
  )
  println("")

  // Writing goes back out in the preferred form, whatever shape the moment has —
  // as long as it can name an instant at all.
  println(imf.http_text())
  println(rfc850.http_text())
  println("")

  // A two-digit year in an HTTP date is not the same rule as the one in ASN.1.
  // RFC 6265 says 69 and under mean the 2000s, so this is 2069, not 1969. The
  // two-digit form only appears in the obsolete RFC 850 spelling.
  let cookie_year = @moondate.http("Sunday, 06-Nov-69 08:49:37 GMT")
  println("2069 or 1969? " + cookie_year.to_string())
  println("")

  // ---- ASN.1 --------------------------------------------------------------
  //
  // Certificates carry their validity in UTCTime or GeneralizedTime. UTCTime
  // drops the century; RFC 5280 fills it back in with 50 as the pivot, which is
  // the opposite of HTTP's 70.

  let utc_time = @moondate.asn1("260922143000Z") // UTCTime, DER form
  let generalized = @moondate.asn1("20260922143000Z") // GeneralizedTime

  println(utc_time)
  println(generalized)
  println(
    "both parse to the same instant: " +
    (utc_time.epoch() == generalized.epoch()).to_string(),
  )
  println("")

  // The pivot, both ways. 49 is 2049; 50 is 1950.
  println(@moondate.asn1("491231235959Z").to_string())
  println(@moondate.asn1("500101000000Z").to_string())
  println("")

  // Writing always uses GeneralizedTime: it spells the century out, so nothing
  // has to be guessed on the way back in.
  println(@moondate.parse("2026-09-22T14:30:00Z").asn1_text())
  println(@moondate.parse("2049-12-31T23:59:59Z").asn1_text())
  println(@moondate.parse("2050-01-01T00:00:00Z").asn1_text())
  println("")

  // ---- refusals -----------------------------------------------------------
  //
  // Neither reader guesses. A short field, a missing `Z`, or a letter where a
  // digit belongs comes back as an error with the reason inside it.

  let asn1_attempts = [
    "260922143000A", // right length, but DER requires the Z
     "2609221430", // truncated
     "2026-09-22", // RFC 3339, not ASN.1
  ]
  for text in asn1_attempts {
    println(text + " -> " + asn1_error(text))
  }
  println("")

  let http_attempts = [
    "Sun, 06 Nov 1994", // the day without the clock
     "Sun Nov  6 08:49:37", // asctime with the year cut off
     "yesterday", // not a date at all
  ]
  for text in http_attempts {
    println(text + " -> " + http_error(text))
  }
}
