package Cpanel::Email::Setup::MobileConfig;

# cpanel - Cpanel/Email/Setup/MobileConfig.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception             ();
use Cpanel::LoadModule            ();
use Cpanel::Email::Setup          ();
use Cpanel::Validate::EmailCpanel ();
use Cpanel::Validate::Username    ();
use Cpanel::FileUtils::Read       ();
use Cpanel::DAV::Provider         ();

use Try::Tiny;

our $TEMPLATE_DIR = '/usr/local/cpanel/base/backend';

#########################################################################
#
# Method:
#   generate
#
# Description:
#   Generates a signed Apple .mobileconfig file for the specified
#   mail account
#
# Parameters:
#
#   account           - An email account [string]
#   (required)
#
#   use_ssl           - Return secure or insecure config [boolean]
#   (required)
#
# Returns:
#   A signed .mobileconfig file
#

sub generate {
    my (%OPTS) = @_;

    foreach my $required (qw(account use_ssl)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !length $OPTS{$required};
    }

    my $use_ssl = $OPTS{'use_ssl'};
    my $account = $OPTS{'account'};

    if ( !$account || !( Cpanel::Validate::EmailCpanel::is_valid($account) || Cpanel::Validate::Username::is_valid_system_username($account) ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid account name.', [$account] );
    }

    require Cpanel::Email::AutoConfig::Settings;
    my $email_config_ref = Cpanel::Email::AutoConfig::Settings::get_autoconfig_data( $account, 'imap' );
    my ( $inc_host, $out_host, $imapport, $smtpport );
    if ($use_ssl) {
        $inc_host = $email_config_ref->{'inbox_host'};
        $out_host = $email_config_ref->{'smtp_host'};
        $imapport = $email_config_ref->{'inbox_port'};
        $smtpport = $email_config_ref->{'smtp_port'};
    }
    else {
        $inc_host = $out_host = $email_config_ref->{'mail_domain'};
        $imapport = $email_config_ref->{'inbox_insecure_port'};
        $smtpport = $email_config_ref->{'smtp_insecure_port'};
    }

    my $props = Cpanel::Email::Setup::get_account_properties( $account, $use_ssl );

    my %CONFIG;
    $CONFIG{'usessl_true_false'} = $use_ssl ? 'true' : 'false';
    $CONFIG{'inc_host'}          = $inc_host;
    $CONFIG{'out_host'}          = $out_host;
    $CONFIG{'smtp_port'}         = $smtpport || _get_service_port('submission');
    $CONFIG{'email'}             = $props->{'email'};
    $CONFIG{'acct'}              = $account;
    $CONFIG{'emailid'}           = $props->{'emailid'};
    $CONFIG{'organization'}      = $props->{'organization'};
    $CONFIG{'imap_port'}         = $imapport || _get_service_port( $use_ssl ? 'imaps' : 'imap' );
    $CONFIG{'displayname'}       = $props->{'displayname'};

    # Even without a DAV provider installed, we still use this module for UUID generation
    Cpanel::LoadModule::load_perl_module('Cpanel::DAV::UUID');
    $CONFIG{'config_uuid'} = Cpanel::DAV::UUID::generate( split( m{@}, $props->{'email'} ) );
    $CONFIG{'org_uuid'}    = Cpanel::DAV::UUID::generate( $props->{'organization'}, 'cpanel' );

    my $dav_provider = Cpanel::DAV::Provider::installed();
    if ($dav_provider) {
        Cpanel::LoadModule::load_perl_module('Cpanel::DAV::Config');
        my $dav_obj = Cpanel::DAV::Config::get_conf_object($account);

        # TODO: only get %CONFIG items for the templates we need to process

        #	-- cut use Cpanel::Template ---
        $CONFIG{'dav_port'}          = $use_ssl ? $dav_obj->HTTPS_PORT() : $dav_obj->HTTP_PORT();
        $CONFIG{'caldav_uuid'}       = Cpanel::DAV::UUID::generate( $props->{'organization'}, 'cpanel-caldav' );
        $CONFIG{'carddav_uuid'}      = Cpanel::DAV::UUID::generate( $props->{'organization'}, 'cpanel-carddav' );
        $CONFIG{'dav_principal_url'} = $dav_obj->PRINCIPAL_PATH();

    }

    # TODO: figure out a better way to incorporate archived accounts if needed in the future, the existing template was just a symlink to the non-archived, so it appears to be the same

    # create a map of services to their particular template file
    my %selected_template_map = (
        'carddav' => { displayname => $use_ssl ? 'Secure Contacts Setup' : 'Contacts Setup', template => 'ios.mobileconfig.carddav.tmpl' },
        'caldav'  => { displayname => $use_ssl ? 'Secure Calendar Setup' : 'Calendar Setup', template => 'ios.mobileconfig.caldav.tmpl' },
        'email'   => { displayname => $use_ssl ? 'Secure Email Setup'    : 'Email Setup',    template => 'ios.mobileconfig.email.tmpl' }
    );

    # set default to behave the same as it used to, all options (during account creation)
    if ( ( defined $OPTS{'selected_account_services'} && !$OPTS{'selected_account_services'} ) || !defined $OPTS{'selected_account_services'} ) {
        $OPTS{'selected_account_services'} = 'email,caldav,carddav';
    }

    if ( !$dav_provider ) {
        $OPTS{'selected_account_services'} = 'email';
    }

    # Determine what we want to build in to the .mobileconfig out of: carddav, caldav, email
    $OPTS{'selected_account_services'} =~ s/\s+//g;
    my %selected = map { $_ => 1 } split( /,/, $OPTS{'selected_account_services'} );

    # build our template file based on options selected in form: header + selected + footer
    my $full_template = _process_template( "$TEMPLATE_DIR/ios.mobileconfig.header.tmpl", \%CONFIG );
    foreach my $element ( keys %selected ) {
        if ( defined $selected_template_map{$element} ) {
            $CONFIG{'displayname'} = $props->{'email'} . ' ' . $selected_template_map{$element}->{'displayname'};

            # This only works for individual services, which is currently how this is used, but I can foresee a bug slipping in if the usage is changed but this is not
            # If this is used for multiple services at once (in the same profile) in the future, only the last service will be identified (it goes in the footer)
            $CONFIG{'service'} = $element;
            $full_template .= _process_template( "$TEMPLATE_DIR/" . $selected_template_map{$element}->{'template'}, \%CONFIG );
        }
    }
    $full_template .= _process_template( "$TEMPLATE_DIR/ios.mobileconfig.footer.tmpl", \%CONFIG );

    Cpanel::LoadModule::load_perl_module('Cpanel::SSL::Domain');
    my $assets = Cpanel::SSL::Domain::get_certificate_assets_for_service(
        'service' => 'dovecot',
        'domain'  => $inc_host
    );

    Cpanel::LoadModule::load_perl_module('Cpanel::SSL::Sign');
    return Cpanel::SSL::Sign::smime_sign_with_certificate(
        %$assets,
        'payload' => $full_template,
    );
}

#----------------------------------------------------------------------

sub _get_service_port {
    my $service = shift;

    return ( getservbyname $service, 'tcp' )[2];
}

sub _process_template {
    my ( $config_file_template_path, $config_ref ) = @_;
    my $CRLF = "\r\n";
    my $ret  = '';
    Cpanel::FileUtils::Read::for_each_line(
        $config_file_template_path,
        sub {
            s/\n/$CRLF/g;
            s/\%([^\%]+)\%/$config_ref->{$1}/g;
            $ret .= $_;
        }
    );
    return $ret;
}

1;
