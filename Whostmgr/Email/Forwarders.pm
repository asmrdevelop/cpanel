package Whostmgr::Email::Forwarders;

# cpanel - Whostmgr/Email/Forwarders.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                    ();
use Cpanel::ConfigFiles                  ();
use Cpanel::WildcardDomain::Tiny         ();
use Cpanel::Email::Aliases               ();
use Cpanel::Config::LoadUserDomains      ();
use Cpanel::AccessIds::ReducedPrivileges ();

sub list_forwarders_for_domain {
    my $opts_hr = shift;
    $opts_hr = {} if 'HASH' ne ref $opts_hr;

    my @err_collection;
    foreach my $required_key (qw(user domain)) {
        if ( !$opts_hr->{$required_key} ) {
            push @err_collection, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_key] );
        }
    }
    die Cpanel::Exception::create( 'Collection', [ exceptions => \@err_collection ] ) if scalar @err_collection;

    return _fetch_forwarders_for_user( $opts_hr->{'user'}, [ $opts_hr->{'domain'} ] );
}

sub list_forwarders_for_user {
    my $user = shift;

    die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['user'] ) if !$user;

    my $userdomains       = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my @this_user_domains = grep { $userdomains->{$_} eq $user } keys %{$userdomains};

    return _fetch_forwarders_for_user( $user, \@this_user_domains );
}

sub _fetch_forwarders_for_user {
    my ( $user, $domains_ar ) = @_;

    my $forwarders = {};
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        $user,
        sub {
            # This duplicates logic similar to whats in Cpanel::API::Email::_listforwards()
            foreach my $domain ( @{$domains_ar} ) {
                next if Cpanel::WildcardDomain::Tiny::is_wildcard_domain($domain);

                my $aliases_obj = Cpanel::Email::Aliases->new( domain => $domain );
                for my $alias ( $aliases_obj->get_aliases() ) {

                    # Ignore the entry for the 'default address'/'catch all'
                    # cause it isn't shown in the 'forwarders' UI
                    next if $alias eq '*';

                    for my $addy ( $aliases_obj->get_destinations($alias) ) {
                        next
                          if (
                            $addy =~ m!/autorespond!       # Ignore the 'autoreponders' forwarders (i.e., forwarders piping to ulc/bin/autorespond)
                            || $addy =~ m!/mailman/!       # Ignore the 'mailman' forwarders (i.e., forwarders piping to ulc/3rdparty/mailman/mail/mailman)
                          );

                        if ( $alias =~ m/^owner-(.+\@.+)$/i ) {
                            my $test_if_list = $1;
                            $test_if_list =~ s/\@/_/;
                            if ( !-d $Cpanel::ConfigFiles::MAILMAN_LISTS_DIR . "/$test_if_list" ) {
                                push @{ $forwarders->{$alias} }, $addy;
                            }
                        }
                        elsif ( $addy =~ m/^(.+)-admin\@(.+)$/i ) {
                            my $test_if_list = $1 . '_' . $2;
                            if ( !-d $Cpanel::ConfigFiles::MAILMAN_LISTS_DIR . "/$test_if_list" ) {
                                push @{ $forwarders->{$alias} }, $addy;
                            }
                        }
                        else {
                            push @{ $forwarders->{$alias} }, $addy;
                        }
                    }
                }
            }
            return 1;
        }
    );

    return $forwarders;
}

1;
