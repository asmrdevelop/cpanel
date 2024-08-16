package Cpanel::Locale::Utils::Api1;

# cpanel - Cpanel/Locale/Utils/Api1.pm                Copyright 2022 cPanel L.L.C
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Locale::Utils::Api1 - Api1 calls for Locale

=head1 SYNOPSIS

    use Cpanel::Locale::Utils::Api1;

=head1 DESCRIPTION

This is the Api1 support breakout of Cpanel::Locale

This is not intended to be called directly

=cut

use Cpanel::Locale ();

my $_lh;

sub _api1_maketext {    ## no critic qw(Subroutines::RequireArgUnpacking)                             ## no extract maketext
    $_lh ||= Cpanel::Locale->get_handle();
    $_[0] =~ s{\\'}{'}g;
    my $localized_str = $_lh->makevar(@_);
    if ($Cpanel::Parser::Vars::embtag) {    # PPI NO PARSE -- module will already be there is we care about it

        require Cpanel::Encoder::Tiny;
        $localized_str = Cpanel::Encoder::Tiny::safe_html_encode_str($localized_str);
    }
    elsif ($Cpanel::Parser::Vars::javascript) {    # PPI NO PARSE -- module will already be there is we care about it
        $localized_str =~ s/"/\\"/g;
        $localized_str =~ s/'/\\'/g;
    }
    return {
        status    => 1,
        statusmsg => $localized_str,
    };
}

1;
