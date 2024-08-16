package Whostmgr::Email::Autoresponders;

# cpanel - Whostmgr/Email/Autoresponders.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::PwCache                      ();
use Cpanel::Config::LoadUserDomains      ();
use Cpanel::AccessIds::ReducedPrivileges ();

sub list_auto_responders_for_domain {
    my $opts_hr = shift;
    $opts_hr = {} if 'HASH' ne ref $opts_hr;

    my @err_collection;
    foreach my $required_key (qw(user domain)) {
        if ( !$opts_hr->{$required_key} ) {
            push @err_collection, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_key] );
        }
    }
    die Cpanel::Exception::create( 'Collection', [ exceptions => \@err_collection ] ) if scalar @err_collection;

    return _fetch_autoresponders_for_user( $opts_hr->{'user'}, [ $opts_hr->{'domain'} ] )->{ $opts_hr->{'domain'} } || [];
}

sub list_auto_responders_for_user {
    my $user = shift;
    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['user'] ) if !$user;

    my $userdomains       = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my @this_user_domains = grep { $userdomains->{$_} eq $user } keys %{$userdomains};

    return _fetch_autoresponders_for_user( $user, \@this_user_domains );
}

# This reimplements functionality available in a cPanel function because that
# code only works for the current user.  This reimplementation of
# Cpanel::API::Email::_listautoresponders allows a reseller to get the
# autoresponders for a specific user.
sub _fetch_autoresponders_for_user {
    my ( $user, $domains_ar ) = @_;

    my $autoresponders = {};
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        $user,
        sub {
            if ( opendir my $dh, get_auto_responder_dir($user) ) {
                my @all_responders = grep { !/^\.{1,2}$/ && !/\.conf$/ && !/\.json$/ } readdir $dh;
                closedir $dh;

                my $domain_matcher_str = join '|', map { "\Q$_\E" } @{$domains_ar};
                my $match_regex        = qr/\@($domain_matcher_str)$/;
                foreach my $responder (@all_responders) {
                    if ( $responder =~ $match_regex ) {
                        push @{ $autoresponders->{$1} }, $responder;
                    }
                }
            }
            return 1;
        }
    );

    return $autoresponders;
}

sub get_auto_responder_dir {
    my $user    = shift;
    my $homedir = Cpanel::PwCache::gethomedir($user)
      or die Cpanel::Exception->create( 'The system could not locate the home directory for the [asis,cPanel] user “[_1]”.', [$user] );
    return "$homedir/.autorespond";
}

1;
