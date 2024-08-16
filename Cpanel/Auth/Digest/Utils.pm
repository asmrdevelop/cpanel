package Cpanel::Auth::Digest::Utils;

# cpanel - Cpanel/Auth/Digest/Utils.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Auth::Digest::DB::Manage ();
use Cpanel::CheckPass::UNIX          ();
use Cpanel::Locale                   ();
use Cpanel::PwCache                  ();

my $locale;

sub set_digest_auth {
    my ($args) = @_;
    my $user   = $args->{'user'};
    my $pass   = $args->{'password'};
    my $enabledigest =
      exists $args->{'digestauth'}
      ? $args->{'digestauth'}
      : $args->{'enabledigest'};
    $locale ||= Cpanel::Locale->get_handle();

    my ( $result, $reason );
    if ( !length $user ) {
        $result = 0;
        $reason = $locale->maketext('No user name supplied.');
    }
    elsif ( !defined( ( Cpanel::PwCache::getpwnam($user) )[0] ) ) {
        $result = 0;
        $reason = $locale->maketext('The specified user does not exist.');
    }
    elsif ( $enabledigest && !length $pass ) {
        $result = 0;
        $reason = $locale->maketext('No password supplied.');
    }
    else {
        if ($enabledigest) {
            if ( my $stored = ( Cpanel::PwCache::getpwnam($user) )[1] ) {
                if ( !length $stored ) {
                    $result = 0;
                    $reason = $locale->maketext('Digest Authentication could not be enabled because we could not fetch the current crypted password.');
                }
                elsif ( $stored eq '!!' ) {
                    $result = 0;
                    $reason = $locale->maketext('Digest Authentication could not be enabled because there is no crypted password set.');
                }
                elsif ( $stored =~ m/(?:\*LOCKED\*|^\!\!)/ ) {
                    $result = 0;
                    $reason = $locale->maketext('Digest Authentication could not be enabled because the account is suspended.');
                }
                elsif ( $pass && $stored && Cpanel::CheckPass::UNIX::checkpassword( $pass, $stored ) ) {
                    if ( Cpanel::Auth::Digest::DB::Manage::set_password( $user, $pass ) ) {

                        $result = 1;
                        $reason = $locale->maketext('Digest Authentication enabled.');
                    }
                    else {
                        $result = 0;
                        $reason = $locale->maketext('Digest Authentication could not be enabled because the database could not be updated.');
                    }

                }
                else {
                    $result = 0;
                    $reason = $locale->maketext('Digest Authentication could not be enabled because the supplied password was not correct.');
                }
            }
            else {
                $result = 0;
                $reason = $locale->maketext('Could not authenticate current password.');
            }
        }
        else {
            if ( Cpanel::Auth::Digest::DB::Manage::remove_entry($user) ) {
                $result = 1;
                $reason = $locale->maketext('Digest Authentication disabled.');
            }
            else {
                $result = 0;
                $reason = $locale->maketext('Digest Authentication could not be disabled because the database could not be updated.');
            }
        }
    }
    return { 'result' => $result, 'reason' => $reason };
}

1;
