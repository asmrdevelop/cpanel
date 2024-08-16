package Cpanel::ContactInfo;

# cpanel - Cpanel/ContactInfo.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache::Build          ();
use Cpanel::AcctUtils::Owner        ();
use Cpanel::AccessIds               ();
use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::ContactInfo::Email      ();
use Cpanel::CustInfo::Get           ();
use Cpanel::CustInfo::Impl          ();
use Cpanel::PwCache                 ();
use Cpanel::Team::Config            ();

my $limit_of_users_until_mass_pwdata_load = 3;    # For any amount of users past this number, it's faster to load PWDATA from cache all at once

sub get_contactinfo_for_user {
    my ( $user, $cpd_ref ) = @_;
    my $cref = fetch_contactinfo( { $user => 1 }, { $user => $cpd_ref } );

    return $cref->{$user};
}

sub fetch_contactinfo {
    my ( $ref_user_domains, $ref_CPDATA ) = @_;

    my %CONTACT_INFO;
    my $contact_fields = Cpanel::CustInfo::Get::get_active_contact_fields();

    my @cpuser_contact_keys = map { $contact_fields->{$_}{'cpuser_key'} || () } keys %{$contact_fields};
    my %PWDATA;
    my $loaded_pwdata = 0;

    foreach my $user ( keys %{$ref_user_domains} ) {
        $CONTACT_INFO{$user} ||= {};

        if ( $user eq 'root' ) {
            _fill_contactinfo_for_root( $CONTACT_INFO{'root'} );
        }
        elsif ( $ENV{'TEAM_USER'} ) {
            _fill_team_contact_info( $CONTACT_INFO{$user}, $contact_fields, $user );
        }
        else {
            $ref_CPDATA->{$user} ||= Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);

            # If the CPUSER data for the user is missing keys, sync their contact info and reload the CPUSER data
            if ( grep { !exists $ref_CPDATA->{$user}{$_} } @cpuser_contact_keys ) {
                if ( !$loaded_pwdata ) {
                    %PWDATA        = ( scalar keys %{$ref_user_domains} > $limit_of_users_until_mass_pwdata_load ) ? map { $_->[0] => $_ } @{ Cpanel::PwCache::Build::fetch_pwcache() } : ();
                    $loaded_pwdata = 1;
                }
                require Cpanel::ContactInfo::Sync;
                Cpanel::ContactInfo::Sync::sync_contact_info( $user, ( $PWDATA{$user} ? ( $PWDATA{$user}->[7], $PWDATA{$user}->[2], $PWDATA{$user}->[3] ) : () ) );
                $ref_CPDATA->{$user} = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
            }
            _fill_contact_info_from_cpuserdata( $CONTACT_INFO{$user}, $ref_CPDATA->{$user}, $contact_fields );
        }
    }

    return \%CONTACT_INFO;
}

sub _fill_contact_info_from_cpuserdata {
    my ( $contactinfo_ref, $cpuserdata_ref, $contact_fields ) = @_;

    %{$contactinfo_ref} = (    #
        map {                  #
            $_ => (
                length $cpuserdata_ref->{ $contact_fields->{$_}{'cpuser_key'} } ?    #
                  $cpuserdata_ref->{ $contact_fields->{$_}{'cpuser_key'} }
                : $contact_fields->{$_}{'default'}
            )                                                                        #
          }    #
          grep { $contact_fields->{$_}{'cpuser_key'} } keys %{$contact_fields}    #
    );

    $contactinfo_ref->{'emails'} = $cpuserdata_ref->contact_emails_ar();

    return 1;
}

sub _fill_team_contact_info {
    my ( $contactinfo_ref, $contact_fields, $team_user_name ) = @_;
    my $preferences_data = {};
    my $home_dir         = Cpanel::PwCache::gethomedir( $ENV{'TEAM_OWNER'} );

    my $preferences_ref = Cpanel::AccessIds::do_as_user(
        $ENV{'TEAM_OWNER'},
        sub {
            if ( !defined $Cpanel::user ) {
                require Cpanel;
                Cpanel::initcp();
            }
            return Cpanel::CustInfo::Impl::fetch_preferences(
                appname   => 'cpaneld',
                cpuser    => $ENV{'TEAM_OWNER'},
                cphomedir => $home_dir,
                username  => $team_user_name,
            );
        }
    );
    foreach my $preference ( @{$preferences_ref} ) {
        $preferences_data->{ $preference->{'name'} } = $preference->{'enabled'};
    }
    %{$contactinfo_ref} = (    #
        map {                  #
            $_ => (
                length $preferences_data->{ $contact_fields->{$_}{'cpuser_key'} } ?    #
                  $preferences_data->{ $contact_fields->{$_}{'cpuser_key'} }
                : $contact_fields->{$_}{'default'}
            )                                                                          #
          }    #
          grep { $contact_fields->{$_}{'cpuser_key'} } keys %{$contact_fields}    #
    );
    my $team_user = Cpanel::Team::Config::get_team_user($team_user_name);
    my @emails    = grep { length } @{$team_user}{qw (contact_email secondary_contact_email )};
    $contactinfo_ref->{'emails'} = \@emails;
    return 1;
}

sub _fill_contactinfo_for_root {
    my ($contact_info_ref) = @_;

    my $wwwacct_cf = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my %EMAILS;
    foreach my $type ( 'CONTACTEMAIL', 'CONTACTPAGER' ) {
        foreach my $email ( Cpanel::ContactInfo::Email::split_multi_email_string( $wwwacct_cf->{$type} ) ) {
            $EMAILS{$email} = 1;
        }
    }
    $contact_info_ref->{'emails'} = [ keys %EMAILS ];

    return 1;
}

# Currently only used for cpaddons legacy
sub getownercontact {
    my ( $user, %skipowner ) = @_;

    return if !$user;

    my $owner = Cpanel::AcctUtils::Owner::getowner($user);
    if ( !$skipowner{$owner} ) {
        my $cpuser_obj = Cpanel::Config::LoadCpUserFile::load($owner);
        return $cpuser_obj->contact_emails_ar()->[0] // ();
    }
    return;
}

1;
