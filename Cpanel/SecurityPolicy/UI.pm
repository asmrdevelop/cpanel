package Cpanel::SecurityPolicy::UI;

# cpanel - Cpanel/SecurityPolicy/UI.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my $sent_header = 0;

*process_template = \&main::process_template;

sub xml_header {
    if ( !$sent_header ) {
        $sent_header = 1;
        print "HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-type: text/xml\r\n\r\n";
    }
    return;
}

sub text_header {
    if ( !$sent_header ) {
        $sent_header = 1;
        print "HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n";
    }
    return;
}

sub json_header {
    if ( !$sent_header ) {
        $sent_header = 1;
        print "HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n";
    }
    return;
}

sub html_http_header {
    if ( !$sent_header ) {
        $sent_header = 1;
        print "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-type: text/html\r\n\r\n";
    }
    return;
}

sub html_header {
    my $template_vars_hr = shift;
    html_http_header();

    my $policy_css = main::_get_login_file_url( 'policy',          'css' );
    my $top_logo   = main::_get_login_file_url( 'images/top-logo', 'gif' );

    return main::_pushdoc( 'securitypolicy_header', { 'policy_css' => $policy_css, 'top_logo' => $top_logo, ( $template_vars_hr ? %$template_vars_hr : () ) } );
}

sub html_footer {
    return main::_pushdoc('securitypolicy_footer');
}

sub force_redirect {
    my ($url) = @_;
    if ( !$sent_header ) {
        $sent_header = 1;
        print "HTTP/1.1 302 Temporary Redirect\r\nLocation: $url\r\n\r\n";
    }
    return;
}

sub xml_simple_errormsg {
    my $msg = shift || 'Unspecified error';
    xml_header();
    print qq{<?xml version="1.0" ?>\n<cpanelresult>\n<error>$msg</error><data>\n<result>0</result>\n<reason>};
    print $msg;
    print qq{</reason>\n</data>\n</cpanelresult>};
}

sub json_simple_errormsg {
    my $msg = shift || 'Unspecified error';
    json_header();
    print qq[{"data":{"reason":"$msg","result":"0"},"error":"$msg","type":"text"}\r\n];
}

sub text_simple_errormsg {
    my $msg = shift || 'Unspecified error';
    text_header();
    print $msg;
}

1;
