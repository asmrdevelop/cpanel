package Cpanel::SSL::Auto::Purge;

# cpanel - Cpanel/SSL/Auto/Purge.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Purge - Purge a user from the AutoSSL sytem

=head1 SYNOPSIS

  Cpanel::SSL::Auto::Purge::purge_user('theuser');

=head1 DESCRIPTION

Removes a user from all AutoSSL providers history.  This may
include a queue or other system the provider implements.

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::Autodie                 ();
use Cpanel::SSL::Auto::Exclude::Get ();
use Cpanel::SSL::Auto::Utils        ();
use Cpanel::SSL::Auto::Loader       ();
use Cpanel::SSL::Auto::Problems     ();
use Try::Tiny;

=head2 purge_user($username)

Remove a user from the AutoSSL system.  This will
delete all of their pending items, configuration,
excluded items, and problem logs.

=cut

sub purge_user {
    my ($username) = @_;

    for my $mname ( Cpanel::SSL::Auto::Utils::get_provider_module_names() ) {
        try {
            my $ns = Cpanel::SSL::Auto::Loader::get_and_load($mname);

            $ns->new()->ON_ACCOUNT_TERMINATION($username);
        }
        catch {
            warn $_;
        };
    }

    Cpanel::SSL::Auto::Problems->new()->purge_user($username);

    my $exclude_file_path = Cpanel::SSL::Auto::Exclude::Get::get_user_excludes_file_path($username);
    Cpanel::Autodie::unlink_if_exists($exclude_file_path);

    return;
}

1;
