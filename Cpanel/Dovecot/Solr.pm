package Cpanel::Dovecot::Solr;

# cpanel - Cpanel/Dovecot/Solr.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache ();
use Cpanel::Autodie ();

our $SOLR_IS_INSTALLED_TEST_FILE = '/usr/local/cpanel/3rdparty/scripts/cpanel_dovecot_solr_isonline';

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::Solr - Utils for working with the solr install used for dovecot

=head1 SYNOPSIS

    use Cpanel::Dovecot::Solr;

    my $installed = Cpanel::Dovecot::Solr::is_installed();

=cut

=head2 is_installed()

Determine if the solr server is installed for use with dovecot.

Returns 1 if solr is installed.

Returns 0 if solr is not installed.

=cut

sub is_installed {
    if ( Cpanel::Autodie::exists($SOLR_IS_INSTALLED_TEST_FILE) && Cpanel::PwCache::getpwnam_noshadow('cpanelsolr') ) {
        return 1;
    }
    return 0;
}

1;
