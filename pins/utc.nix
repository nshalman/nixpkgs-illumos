# A time in seconds since 1970 (a pin's date) as a UTC date: seconds, as given; the year, month, day, hour, minute
# and second as numbers; stamp, YYYYMMDDTHHMMSSZ, SmartOS's build stamp form; date, YYYY-MM-DD; monthName, the month
# in English (as `LC_ALL=C date +%B` gives it). Days to a civil date as in Howard Hinnant's days_from_civil inverse
# (https://howardhinnant.github.io/date_algorithms.html#civil_from_days), for times from 1970 on.
seconds:

let
  inherit (builtins) div;
  pad = n: s: if builtins.stringLength s < n then pad n ("0" + s) else s;
  days = div seconds 86400;
  inDay = seconds - days * 86400;
  # days since 0000-03-01, in 400-year eras of 146097 days; years counted from March, so a leap day is a year's last
  z = days + 719468;
  era = div z 146097;
  dayOfEra = z - era * 146097;
  yearOfEra = div (dayOfEra - div dayOfEra 1460 + div dayOfEra 36524 - div dayOfEra 146096) 365;
  dayOfYear = dayOfEra - (365 * yearOfEra + div yearOfEra 4 - div yearOfEra 100);
  monthFromMarch = div (5 * dayOfYear + 2) 153;
  month = if monthFromMarch < 10 then monthFromMarch + 3 else monthFromMarch - 9;
  year = yearOfEra + era * 400 + (if month <= 2 then 1 else 0);
  day = dayOfYear - div (153 * monthFromMarch + 2) 5 + 1;
  hour = div inDay 3600;
  minute = div (inDay - hour * 3600) 60;
  second = inDay - hour * 3600 - minute * 60;
  two = n: pad 2 (toString n);
in
assert seconds >= 0;
{
  inherit
    seconds
    year
    month
    day
    hour
    minute
    second
    ;
  stamp = "${pad 4 (toString year)}${two month}${two day}T${two hour}${two minute}${two second}Z";
  date = "${pad 4 (toString year)}-${two month}-${two day}";
  monthName = builtins.elemAt [
    "January"
    "February"
    "March"
    "April"
    "May"
    "June"
    "July"
    "August"
    "September"
    "October"
    "November"
    "December"
  ] (month - 1);
}
