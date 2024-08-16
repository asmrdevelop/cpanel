
# cpanel - Cpanel/ModSecurity/Admin.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ModSecurity::Admin;

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny  ();
use Cpanel::Config::userdata              ();
use Cpanel::ConfigFiles::Apache::vhost    ();
use Cpanel::Config::userdata              ();
use Cpanel::Config::userdata::UpdateCache ();
use Cpanel::Hooks                         ();
use Cpanel::HttpUtils::ApRestart::BgSafe  ();
use Cpanel::Locale 'lh';
use Cpanel::Validate::Domain ();

=head1 NAME

Cpanel::ModSecurity::Admin

=head1 DESCRIPTION

This module implements most of the functionality of bin/admin/Cpanel/modsecurity.

NOTE: For security purposes, this function must validate that the domains belong
to the specified user. The modsecurity adminbin relies upon this check.

NOTE also: This module is / should be unshipped.

=head1 SUBROUTINES

=head2 adjust_secruleengineoff()

=head3 Description

Enable or disable ModSecurity for one or more domains.

=head3 Arguments

Accepts named arguments:

  - 'user': The user whose domains are being adjusted
  - 'domains': An array ref of one or more domains
  - 'state': A boolean value to set the state of 'secruleengineoff' in the userdata
  - 'restart': A boolean value indicating whether to restart Apache.

=head3 Returns

 Meaning of returned data:
   'status': There was at least one domain passed in, and the operation succeeded for all domains that were passed in.
   'any_ok': Of the domains that were passed in, there was at least one for which the operation succeeded.
   'problems': An array ref of zero or hashes representing failures that occurred. Each hash has the following structure:
          'domain': The domain which triggered the error, if any.
       'exception': The error string.

=cut

sub adjust_secruleengineoff {
    my %args = @_;
    my ( $user, $domains_ar, $state, $restart ) = delete @args{qw(user domains state restart)};
    die lh()->maketext(q{You did not provide a required attribute for the [asis,VirtualHost] adjustment.}) . "\n" if grep { !defined } $user, $domains_ar, $state, $restart;
    die lh()->maketext( q{The system received unexpected attributes for the [asis,VirtualHost] adjustment: [list_and_quoted,_1]}, [ keys %args ] ) . "\n" if %args;

    Cpanel::Hooks::hook(
        {
            'category' => 'ModSecurity',
            'event'    => 'adjust_secruleengineoff',
            'stage'    => 'pre',
        },
        { 'user' => $user }
    );

    my ( $any_ok, $status, @problems ) = ( 0, 1 );
    for my $domain (@$domains_ar) {
        if (
            eval {
                _validate_domain( $user, $domain );

                # Update the userdata
                Cpanel::Config::userdata::update_domain_datafield( $user, $domain, 'secruleengineoff', $state )
                  or die lh()->maketext( q{An error occurred during the [asis,userdata] update for domain “[_1]”.}, $domain ) . "\n";
            }
        ) {
            $any_ok = 1;
        }
        else {
            push @problems, { domain => $domain, exception => $@ };
            $status = 0;
        }
    }

    $status &= $any_ok;    # (if the above loop had 0 iterations, treat that as a failure too)

    if ($any_ok) {

        # Update the /var/cpanel/userdata/<user>/cache file, which our API (among other things) uses to produce a quick list
        Cpanel::Config::userdata::UpdateCache::update($user);

        # Update just this user's vhosts based on the new userdata
        my ( $vhost_update_ok, $msg ) = Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($user);
        $status &= $vhost_update_ok;

        if ( !$vhost_update_ok ) {
            push @problems, { exception => lh()->maketext( 'The system could not update the [asis,VirtualHost] for “[_1]”: [_2]', $user, $msg ) };
        }

        # Queue a deferred apache restart
        if ($restart) {
            Cpanel::HttpUtils::ApRestart::BgSafe::restart();
        }
    }

    Cpanel::Hooks::hook(
        {
            'category' => 'ModSecurity',
            'event'    => 'adjust_secruleengineoff',
            'stage'    => 'post',
        },
        { 'user' => $user }
    );

    return {
        status   => $status,
        any_ok   => $any_ok,
        problems => \@problems,
    };
}

# Cpanel::Config::userdata already does its own validation on the domain, but since this is
# used by an adminbin, we want to be extra careful with the data it passes through.
sub _validate_domain {
    my ( $user, $domain ) = @_;

    my ( $valid, $msg ) = Cpanel::Validate::Domain::validwildcarddomain( $domain, 1 );
    $valid or die lh()->maketext( 'The domain “[_1]” is not valid: [_2]', $domain, $msg ) . "\n";

    $domain !~ m{/}    # just in case
      or die lh()->maketext( 'The domain “[_1]” contains a slash.', $domain ) . "\n";

    Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($domain) eq $user
      or die lh()->maketext( 'The domain “[_1]” does not belong to “[_2]”.', $domain, $user ) . "\n";

    return 1;
}

1;
