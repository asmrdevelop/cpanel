package Cpanel::Email::AutoConfig::Settings;

# cpanel - Cpanel/Email/AutoConfig/Settings.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ActiveSync             ();
use Cpanel::Config::HasCpUserFile  ();
use Cpanel::Config::LoadCpConf     ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Dovecot                ();
use Cpanel::Exim::Ports            ();
use Cpanel::LoadFile               ();
use Cpanel::LoadModule             ();
use Cpanel::SSL::Domain            ();
use Cpanel::Services::Enabled      ();

=encoding utf-8

=head1 NAME

Cpanel::Email::AutoConfig::Settings - Settings for email accounts

=head1 SYNOPSIS

    use Cpanel::Email::AutoConfig::Settings;

    my $settings_for_imap_smtp = Cpanel::Email::AutoConfig::Settings::client_settings('bob@domain.tld');

    my $has_plaintext_authentication = Cpanel::Email::AutoConfig::Settings::has_plaintext_authentication();

    my $pop3_autoconfig_data = Cpanel::Email::AutoConfig::Settings::get_autoconfig_data('bob@domain.tld','pop3');
    my $imap_autoconfig_data = Cpanel::Email::AutoConfig::Settings::get_autoconfig_data('bob@domain.tld','imap');

=head1 DESCRIPTION

Obtains settings for specific email accounts to be used
to manually configure an email client or with an autoconfig
or autodiscovery service.

=cut

=head2 client_settings

Returns the client settings needed to manually configure an email account in a mail client.

=over 2

=item Input

=over 3

=item C<SCALAR>

    The email account to get the settings for:

    Example: _mainaccount@domain.tld, _archive@domain.tld, someone@domain.tld

=back

=item Output

=over 3

=item C<HASHREF>

    Example

    {
      'domain' => 'domain.tld',
      'inbox_host' => 'server.domain.tld',
      'smtp_username' => 'nick@domain.tld',
      'smtp_port' => 465,
      'inbox_service' => 'imap',
      'inbox_port' => 993,
      'inbox_insecure_port' => 143,
      'smtp_insecure_port' => '25',
      'from_archiving' => 0,
      'display' => 'nick@domain.tld',
      'mail_domain' => 'mail.domain.tld',
      'account' => 'nick@domain.tld',
      'smtp_host' => 'server.domain.tld',
      'has_plaintext_authentication' => 1,
      'inbox_username' => 'nick@domain.tld'
    }

=back

=back

=cut

sub client_settings {
    my ($account) = @_;

    my $data_ref = get_autoconfig_data( $account, 'imap' );
    $data_ref->{'account'}                      = $account;
    $data_ref->{'from_archiving'}               = $account =~ m{^_archive} ? 1 : 0;
    $data_ref->{'has_plaintext_authentication'} = has_plaintext_authentication();
    $data_ref->{'activesync_available'}         = Cpanel::ActiveSync::is_activesync_available_for_user($account);
    $data_ref->{'activesync_port'}              = Cpanel::ActiveSync::get_ports()->{'ssl'};
    return $data_ref;
}

=head2 has_plaintext_authentication

Determine if the server allows plaintext authentication (passwords over a clear text channel without ssl/tls)

=over 2

=item Input

=over 3

=item None

=back

=item Output

=over 3

=item Returns 1 if the server allows plain text authentication

=item Returns 0 if the server does not allow plain text authentication (ssl/tls only)

=back

=back

=cut

sub has_plaintext_authentication {
    my $plaintext_auth = Cpanel::LoadFile::load_if_exists($Cpanel::Dovecot::PLAINTEXT_CONFIG_CACHE_FILE);

    # This is a disable file, so "yes" means "disabled"
    return ( length $plaintext_auth && $plaintext_auth =~ m{yes} ) ? 0 : 1;
}

=head2 get_autoconfig_data

Returns the settings needed for the autoconfig and/or autodiscover service for a given email account.
This returns a subset of what client_settings does.

=over 2

=item Input

=over 3

=item C<SCALAR>

    The email account to get the autoconfig data for:

    Example: _mainaccount@domain.tld, _archive@domain.tld, someone@domain.tld

=item C<SCALAR>

    The inbox service to connect to

    Example: imap, pop3

=back

=item Output

=over 3

=item C<HASHREF>

    Example

    {
      'domain' => 'domain.tld',
      'inbox_host' => 'server.domain.tld',
      'smtp_username' => 'nick@domain.tld',
      'smtp_port' => 465,
      'inbox_service' => 'imap',
      'inbox_port' => 993,
      'inbox_insecure_port' => 143,
      'smtp_insecure_port' => '25',
      'display' => 'nick@domain.tld',
      'mail_domain' => 'mail.domain.tld',
      'smtp_host' => 'server.domain.tld',
      'inbox_username' => 'nick@domain.tld'
    }

=back

=back

=cut

sub get_autoconfig_data {
    my ( $email, $inbox_service ) = @_;

    if ( !$inbox_service || $inbox_service !~ m{^pop3|imap$} ) {
        $inbox_service = _get_default_inbox_service();
    }

    my $domain;
    if ($email) {
        if ( $email =~ m{\@(.*)} ) {
            $domain = $1;
        }
        elsif ( Cpanel::Config::HasCpUserFile::has_cpuser_file($email) ) {
            $domain = Cpanel::Config::LoadCpUserFile::loadcpuserfile($email)->{'DOMAIN'};
        }
    }

    if ( !$domain ) {
        $domain = $ENV{'HTTP_X_FORWARDED_HOST'} || $ENV{'HTTP_HOST'};
        $domain =~ s{\Aauto(?:discover|config)\.}{};
    }

    my $get_cn_name_for = length $email ? $email : $domain;

    die "No domain can be determined.\n" if !length $domain;

    my ( $inbox_ok, $inbox_ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $get_cn_name_for, { 'service' => 'dovecot', 'add_mail_subdomain' => 1 } );
    if ( !$inbox_ok || !ref $inbox_ssl_domain_info ) {
        die "SSL::get_cn_name failed to return a valid $inbox_service ssldomain for $get_cn_name_for: " . $inbox_ssl_domain_info;
    }
    my $inbox_host = $inbox_ssl_domain_info->{'ssldomain'};
    die "No $inbox_service ssldomain!\n" if !length $inbox_host;

    my ( $smtp_ok, $smtp_ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $get_cn_name_for, { 'service' => 'exim', 'add_mail_subdomain' => 1 } );
    if ( !$smtp_ok || !ref $smtp_ssl_domain_info ) {
        die "SSL::get_cn_name failed to return a valid smtp ssldomain for $get_cn_name_for: " . $smtp_ssl_domain_info;
    }
    my $smtp_host = $smtp_ssl_domain_info->{'ssldomain'};
    die "No SMTP ssldomain!\n" if !length $smtp_host;

    my $inbox_port          = $inbox_service eq 'imap' ? 993 : 995;
    my $inbox_insecure_port = $inbox_service eq 'imap' ? 143 : 110;
    my $smtp_port           = ( Cpanel::Exim::Ports::get_secure_ports() )[0];

    # We don't want this to be port 25, since that's for server-to-server
    # communication, not end user-to-server communication.  If the user has set
    # up a port other than 25, honor that preference.
    my $smtp_insecure_port = ( grep { $_ != 25 } Cpanel::Exim::Ports::get_insecure_ports() )[0] // 587;

    my ( $inbox_username, $smtp_username ) = ($email) x 2;

    my $display;

    my $is_archive = $email && $email =~ m{\A_archive\@};
    if ($is_archive) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        $display = Cpanel::Locale->get_handle()->maketext( 'Archive: [_1]', $domain );
    }
    elsif ( $email && $email =~ m{\A_mainaccount\@} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        $display = Cpanel::Locale->get_handle()->maketext( 'Main Domain: [_1]', $domain );
    }
    else {
        $display = $email || $domain;
    }

    my %activesync_details = ( activesync_available => 0 );
    if ( $inbox_username && Cpanel::ActiveSync::is_activesync_available_for_user($inbox_username) ) {
        my $ports = Cpanel::ActiveSync::get_ports();
        %activesync_details = (
            activesync_available => 1,
            activesync_host      => $inbox_host,
            activesync_port      => $ports->{ssl},
            activesync_username  => $inbox_username,
        );
    }

    my $ret_hr = {
        inbox_service       => $inbox_service,
        inbox_username      => $inbox_username || '%EMAILADDRESS%',    # support kmail
        smtp_username       => $smtp_username  || '%EMAILADDRESS%',    # support kmail
        display             => $display,
        domain              => $domain,
        mail_domain         => "mail.$domain",
        inbox_host          => $inbox_host,
        inbox_port          => $inbox_port,
        inbox_insecure_port => $inbox_insecure_port,
        smtp_host           => $smtp_host,
        smtp_port           => $smtp_port,
        smtp_insecure_port  => $smtp_insecure_port,
        %activesync_details,
    };

    for ( keys %$ret_hr ) {
        delete $ret_hr->{$_} if !length;
    }

    return $ret_hr;
}

sub _get_default_inbox_service {
    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    my $use_imap;
    if ( $cpconf_ref->{'autodiscover_mail_service'} && $cpconf_ref->{'autodiscover_mail_service'} eq 'pop3' ) {
        $use_imap = 0;
    }
    else {
        $use_imap = Cpanel::Services::Enabled::is_enabled('imap');
    }

    return $use_imap ? 'imap' : 'pop3';
}

1;
