package Cpanel::Config::SaveWwwAcctConf;

# cpanel - Cpanel/Config/SaveWwwAcctConf.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig      ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Config::FlushConfig     ();
use Cpanel::iContact::Providers     ();
use Cpanel::StringFunc::Trim        ();
use Try::Tiny;

sub savewwwacctconf {
    my ( $conf_ref, $ignore_missing_contacts ) = @_;
    return if ( !$conf_ref || ref $conf_ref ne 'HASH' );
    my %new_conf = %{$conf_ref};
    my %shadow   = (
        'CONTACTPUSHBULLET' => '',
        'CONTACTUIN'        => '',
        'ICQPASS'           => '',
        'ICQUSER'           => '',
    );

    Cpanel::iContact::Providers::augment_shadow_keys( \%shadow );

    my $shadow_file  = $Cpanel::Config::LoadWwwAcctConf::wwwacctconfshadow;
    my $regular_file = $Cpanel::Config::LoadWwwAcctConf::wwwacctconf;

    my %allowed_shadow = %shadow;    #must be a copy
    {

        # Manipulate shadow file, removing anything from conf that belongs in shadow.
        my %read_shadow;
        Cpanel::Config::LoadConfig::loadConfig( $shadow_file, \%read_shadow, '\s+', undef, undef, undef, { 'nocache' => 1 } );

        # Only copy keys that are supposed to be in the shadow file.
        foreach my $key ( sort keys %allowed_shadow ) {
            if ( exists $new_conf{$key} ) {
                $shadow{$key} = $new_conf{$key};
                delete $new_conf{$key};
            }
            else {
                $shadow{$key} = $read_shadow{$key};
            }
        }
        Cpanel::Config::FlushConfig::flushConfig( $shadow_file, \%shadow, ' ', undef, { 'sort' => 1 } );
    }

    my %conf = (
        'ADDR'         => '',
        'ADDR6'        => '',
        'CONTACTEMAIL' => '',
        'CONTACTPAGER' => '',
        'DEFMOD'       => '',
        'ETHDEV'       => '',
        'HOMEDIR'      => '',
        'HOMEMATCH'    => '',
        'HOST'         => '',
        'LOGSTYLE'     => '',
        'NS'           => '',
        'NS2'          => '',
        'NS3'          => '',
        'NS4'          => '',
        'NSTTL'        => '',
        'SCRIPTALIAS'  => '',
        'TTL'          => '',
    );

    #Cpanel::StringFunc::Trim::ws_trim() only called on the non-shadow part as passwords may start or end with s apce
    Cpanel::Config::LoadConfig::loadConfig( $regular_file, \%conf, '\s+', undef, undef, undef, { 'nocache' => 1 } );

    update_contact_emails( \%new_conf, $conf{'CONTACTEMAIL'}, $ignore_missing_contacts );

    delete @conf{ keys %shadow };    # Remove fields in the shadow file.
    foreach my $key ( sort keys %conf ) {
        if ( exists $new_conf{$key} ) {
            $conf{$key} = defined $new_conf{$key} ? Cpanel::StringFunc::Trim::ws_trim( $new_conf{$key} ) : $new_conf{$key};
            delete $new_conf{$key};
        }
    }
    foreach my $new_key ( keys %new_conf ) {
        next if ( !defined $new_conf{$new_key} || $new_conf{$new_key} eq '' );
        $conf{$new_key} = Cpanel::StringFunc::Trim::ws_trim( $new_conf{$new_key} );
    }
    my $status = Cpanel::Config::FlushConfig::flushConfig( $regular_file, \%conf, ' ', undef, { 'sort' => 1 } );
    chmod( 0644, $regular_file ) if defined $regular_file;
    chmod( 0600, $shadow_file )  if defined $shadow_file;

    return $status;
}

sub update_contact_emails {
    my ( $conf_ref, $old_email, $ignore_missing_contacts ) = @_;

    # This module is loaded by Cpanel::Config, so only load these modules when
    # really necessary.
    require Cpanel::Email::UserForward;
    require Cpanel::Exception;

    foreach my $email_user (qw(root cpanel nobody)) {
        my $cur_forwards = Cpanel::Email::UserForward::get_user_email_forward_destination( 'user' => $email_user );

        my $cur_emails = { map { $_ => 1 } ( ref $cur_forwards ? @$cur_forwards : () ) };
        if ( ( !$ignore_missing_contacts && !keys %$cur_emails ) || delete $cur_emails->{$old_email} ) {
            $cur_emails->{ $conf_ref->{'CONTACTEMAIL'} } = 1 if defined $conf_ref->{'CONTACTEMAIL'};
            try {
                Cpanel::Email::UserForward::set_user_email_forward_destination( 'user' => $email_user, 'forward_to' => join( ',', sort keys %$cur_emails ) );
            }
            catch {
                warn Cpanel::Exception::get_string($_);
            };
        }
    }
    return;
}

1;
