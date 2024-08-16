package Whostmgr::XSS;

use Cpanel::Encoder::Tiny ();

sub cleanfield {
    goto &Cpanel::Encoder::Tiny::safe_html_encode_str;
}

1;
