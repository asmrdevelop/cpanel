package Whostmgr::Transfers::Systems::Account;

# cpanel - Whostmgr/Transfers/Systems/Account.pm     Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Cpanel::Auth::Shadow       ();
use Cpanel::DIp::Group         ();
use Cpanel::PwCache            ();
use Cpanel::Themes::Available  ();
use Cpanel::Email::MX          ();
use Whostmgr::Accounts::Create ();
use Whostmgr::Func             ();
use Cpanel::SSL::Setup         ();

use base qw(
  Whostmgr::Transfers::Systems
  Whostmgr::Transfers::SystemsBase::Frontpage
);

sub failure_is_fatal {
    return 1;
}

sub get_relative_time {
    return 5;
}

sub get_phase {
    return 10;
}

sub get_prereq {
    return [];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This creates the cPanel account and system user.') ];
}

sub get_restricted_available {
    return 1;
}

sub get_restricted_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('Force mode is not available in restricted mode.') ];
}

*unrestricted_restore = \&restricted_restore;

sub restricted_restore {
    my ($self) = @_;

    my $createacct          = $self->{'_utils'}->{'flags'}->{'createacct'} ? 1 : 0;
    my $dedicated_ip        = Whostmgr::Func::yesno( $self->{'_utils'}->{'flags'}->{'ip'} );
    my $custom_ip           = $self->_get_custom_ip();
    my $shared_mysql_server = $self->{'_utils'}->{'flags'}->{'shared_mysql_server'} ? 1 : 0;

    my $user = $self->newuser();

    my ($cpuser_data) = $self->{'_utils'}->get_cpuser_data();    # validated in AccountRestoration.pm if restricted

    my $plan = $cpuser_data->{'PLAN'} || 'undefined';

    my $contact_email = $cpuser_data->{'CONTACTEMAIL'} || '';
    if ( $cpuser_data->{'CONTACTEMAIL2'} ) {
        $contact_email .= ';' . $cpuser_data->{'CONTACTEMAIL2'};
    }

    my $cpanel_theme;
    if ( !defined $cpuser_data->{'RS'} || !Cpanel::Themes::Available::is_theme_available( $cpuser_data->{'RS'} ) ) {
        $cpanel_theme = $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME;
        $self->warn( $self->_locale()->maketext( "The user’s account in the archive uses the “[_1]” theme, which does not exist on this server. The system has set the restored account to use the “[_2]” theme.", $cpuser_data->{'RS'}, $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME ) );
    }

    my $createacct_owner = $self->new_owner();

    my $force = $self->{'_utils'}->is_unrestricted_restore() && $self->{'_utils'}->{'flags'}->{'force'} ? 1 : 0;

    $self->out( ( $force                               ? $self->_locale()->maketext("Force Mode: yes")           : $self->_locale()->maketext("Force Mode: no") ) . "\n" );
    $self->out( ( $self->{'_utils'}->{'flags'}->{'ip'} ? $self->_locale()->maketext("Dedicated IP Address: yes") : $self->_locale()->maketext("Dedicated IP Address: no") ) . "\n" );

    if ( $self->was_using_frontpage ) {
        $self->warn( $self->_locale()->maketext("This account used [asis,Microsoft® FrontPage®] on the source server. The local server does not support [asis,FrontPage].") );
    }

    my $account_enhancements = [ map { $_ =~ /ACCOUNT-ENHANCEMENT-([0-9A-Za-z =_-]{1,64})/ } keys %{$cpuser_data} ];

    my $domain = $self->{'_utils'}->main_domain();    # validated in AccountRestoration.pm if restricted
    if ($createacct) {

        # CPANEL-16146: Prevent the best available cert from being installed before SSL.pm runs
        local $Cpanel::SSL::Setup::DISABLED = 1;

        my %WWWACCTCFG = (
            'domain'               => $domain,
            'username'             => $user,
            'password'             => 'HIDDEN',
            'quota'                => 0,
            'cpmod'                => $cpanel_theme,
            'ip'                   => $dedicated_ip,
            'customip'             => $custom_ip,
            'cgi'                  => 'n',
            'maxftp'               => 0,
            'maxsql'               => 0,
            'maxpop'               => 0,
            'maxlst'               => 0,
            'maxsub'               => 0,
            'bwlimit'              => 0,
            'hasshell'             => 0,
            'owner'                => $createacct_owner,
            'plan'                 => $plan,
            'maxpark'              => 0,
            'maxaddon'             => 0,
            'featurelist'          => 'default',
            'contactemail'         => $contact_email,
            'account_enhancements' => $account_enhancements,

            # is_restore allows . and _ in usernames
            #  as well as loose checking on email addresses
            'is_restore'               => 1,
            'forcedns'                 => 1,
            'useregns'                 => 0,
            'force'                    => $force,
            'no_cache_update'          => 0,
            'skip_mysql_dbowner_check' => $shared_mysql_server,
            'mxcheck'                  => Cpanel::Email::MX::cpuser_key_to_mx_compat( $cpuser_data->{ 'MXCHECK-' . $domain } ),
        );

        $WWWACCTCFG{'mailbox_format'} = $cpuser_data->{'MAILBOX_FORMAT'} if $cpuser_data->{'MAILBOX_FORMAT'};

        my ( $result, $reason, $output ) = Whostmgr::Accounts::Create::_createaccount(%WWWACCTCFG);

        if ( !$result ) {
            return ( 0, "Failed to create the account: $reason", $output );
        }

        $self->out($output);

        my ( $status, $statusmsg ) = Cpanel::Auth::Shadow::update_shadow_without_acctlock( $user, '!!' . ( Cpanel::PwCache::getpwnam($user) )[1] );
        return ( 0, $statusmsg ) if !$status;
    }
    else {
        return ( 0, "The createacct flag is required in order to restore an account in restricted restore mode." );
    }

    my ( $uid, $gid, $user_homedir ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3, 7 ];

    if ( !$uid ) {
        return ( 0, "Account creation failed with untrapped error" );
    }

    $self->{'_utils'}->add_restored_domain($domain);

    $self->utils()->set_account_restoration_mutex();

    return ( 1, "Account created" );
}

sub _get_custom_ip {
    my ($self) = @_;

    return $self->{'_utils'}->{'flags'}->{'customip'} if $self->{'_utils'}->{'flags'}->{'customip'};

    my $temp_custom_ip = $self->{'_utils'}->get_ip_address_from_cpuser_data();

    return $temp_custom_ip if $temp_custom_ip && $self->_is_ip_available($temp_custom_ip);
    return q{};
}

sub _is_ip_available {
    my ( $self, $ip ) = @_;

    return 1 if grep { $_ eq $ip } Cpanel::DIp::Group::get_available_ips( $self->new_owner() );
    return 0;
}

1;
