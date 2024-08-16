package Whostmgr::Transfers::Systems::CpUser;

# cpanel - Whostmgr/Transfers/Systems/CpUser.pm      Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

# RR Audit: JNK

use Cpanel::Imports;

use Cpanel::AcctUtils::Account            ();
use Cpanel::Config::CpUser::MigrationData ();
use Cpanel::Config::CpUserGuard           ();
use Cpanel::ConfigFiles                   ();
use Cpanel::DIp::MainIP                   ();
use Cpanel::IP::Loopback                  ();
use Cpanel::Themes::Available             ();
use Cpanel::Userdomains                   ();
use Whostmgr::ACLS                        ();
use Whostmgr::Accounts::Email             ();
use Whostmgr::Packages::Info              ();

use base qw(
  Whostmgr::Transfers::Systems
);

use constant {
    failure_is_fatal         => 1,
    get_phase                => 10,
    get_prereq               => ['Account'],
    get_restricted_available => 1,
};

sub get_summary {
    return [ locale()->maketext('This restores the [asis,cPanel] account’s configuration data.') ];
}

sub get_restricted_summary {
    return [ locale()->maketext('The system discards configuration data that is unknown or that the system cannot validate.') ];
}

*unrestricted_restore = \&restricted_restore;

sub restricted_restore {
    my ($self) = @_;

    # The data is only validated in restricted mode
    my ( $cpuser_data, $skipped ) = $self->{'_utils'}->get_cpuser_data();

    # $skipped will always be empty in unrestricted mode
    $self->_report_skipped_items($skipped);

    return $self->_restore_cpuser_data($cpuser_data);
}

sub _report_skipped_items {
    my ( $self, $skipped_items ) = @_;

    for my $cpuser_key ( keys %$skipped_items ) {
        $self->{'_utils'}->add_skipped_item( $cpuser_key . ': ' . $skipped_items->{$cpuser_key} );
    }

    return;
}

sub _restore_cpuser_data {
    my ( $self, $cpuser_data ) = @_;

    my $username = $self->{'_utils'}->local_username();

    # both of these are probably overly paranoid, but just in case
    return ( 0, "No user was indicated in the restoration process. This should not happen." ) if !$username;
    if ( !$self->{'_utils'}->is_unrestricted_restore() ) {
        return ( 0, "Account $username does not exist." ) if !Cpanel::AcctUtils::Account::accountexists($username);
    }

    return ( 0, "No CpUser data found for “$username”." ) if !$cpuser_data;

    $self->start_action( $self->_locale()->maketext('Restoring [asis,cPanel] user file.') );

    Cpanel::Config::CpUser::MigrationData::update_cpuser_data_hr( $cpuser_data, { 'is_transfer_or_restore' => 1 } );

    # Never safe an 'RS' value that does not exist on this system.
    $cpuser_data->{'RS'} = _theme_is_valid_and_exists_or_default( $cpuser_data->{'RS'} );

    # NB: In restricted mode we forbid nonexistent OWNERs,
    # but in unrestricted mode we allow them. In either mode, though,
    # as of v86 we disallow restoration to a remote-mail reseller.
    $self->_verify_owner_worker_config($cpuser_data);

    # HB-6430: Now, we need to check if we want to selectively take from a
    # potentially existing account. If these prefs were indicated, then keep
    # the indicated cpuser file preferences.
    my $keep     = $self->{'_utils'}{'flags'}{'keep_local_cpuser_values'} || [];
    my $keep_all = grep { $_ eq 'ALL' } @{ $self->{'_utils'}{'flags'}{'keep_local_cpuser_values'} };

    my $restored = 0;
    if ( my $cpuser_guard = Cpanel::Config::CpUserGuard->new($username) ) {

        my %trapper_keeper;
        @trapper_keeper{ keys %$cpuser_data } = values %$cpuser_data;
        if ($keep_all) {
            %trapper_keeper = %{ $cpuser_guard->{'data'} };
        }
        elsif (@$keep) {
            @trapper_keeper{@$keep} = map { $cpuser_guard->{'data'}{$_} } @$keep;

            # ALWAYS keep CHILD_WORKLOADS if it exists so as to not break nodes
            $trapper_keeper{'CHILD_WORKLOADS'} = $cpuser_guard->{'data'}{'CHILD_WORKLOADS'} if exists( $cpuser_guard->{'data'}{'CHILD_WORKLOADS'} );
        }

        # If skipaccount was used, then the account will not have been created
        # and not have any userdata present.  This will cause the IP in the user
        # data to default to 127.0.0.1.  This is never valid for a user account.
        if ( Cpanel::IP::Loopback::is_loopback( $cpuser_guard->{'data'}{'IP'} ) ) {

            $trapper_keeper{'IP'} = Cpanel::DIp::MainIP::getmainsharedip();
        }

        @{ $cpuser_guard->{'data'} }{ keys %trapper_keeper } = values %trapper_keeper;
        my $status = $cpuser_guard->save();

        $restored = $status ? 1 : 0;
    }

    my $gid = ( $self->{'_utils'}->pwnam() )[3];

    my $cpuser_file_path = "$Cpanel::ConfigFiles::cpanel_users/$username";
    my @stat             = stat($cpuser_file_path);
    if ( @stat && $stat[2] & 07777 != 0640 ) {

        #safe chmod not needed
        chmod( 0640, $cpuser_file_path ) or do {
            $self->{'_utils'}->warn( 'Unable to modify permissions on /var/cpanel/users/' . $username . ": $!" );
        };
    }

    if ( @stat && ( $stat[4] != 0 || $stat[5] != $gid ) ) {

        #safe
        chown( 0, $gid, $cpuser_file_path ) or do {
            $self->{'_utils'}->warn( 'Unable to change ownership for /var/cpanel/users/' . $username . ": $!" );
        };
    }

    # We need to call updateuserdomains
    # to ensure /etc/trueuserowners and
    # /etc/*domains* are in sync with the
    # cPanel user data that was just restored.
    $self->start_action( $self->_locale()->maketext('Updating Caches …') );
    Cpanel::Userdomains::updateuserdomains();

    if ( $cpuser_data->{'OUTGOING_MAIL_HOLD'} ) {
        Whostmgr::Accounts::Email::update_outgoing_mail_hold_users_db( 'user' => $self->newuser(), 'hold' => 1 );
    }

    return ( 1, 'CpUser data restored' ) if $restored;

    return ( 0, "Unable to restore CpUser data for “$username”." );
}

sub _verify_owner_worker_config ( $self, $cpuser_data ) {
    my $owner = $cpuser_data->{'OWNER'};

    return if !length $owner;
    return if !Cpanel::AcctUtils::Account::accountexists($owner);

    return if Whostmgr::ACLS::user_has_root($owner);

    if ( my @linked_node_types = _get_linkage_types($owner) ) {
        my $new_owner = $self->get_fallback_new_owner();

        $self->utils()
          ->add_skipped_item(
            locale()->maketext( 'The user, “[_1]”, who owns the account in this backup uses [numerate,_2,a linked node of type,linked nodes of types] [list_and_quoted,_3]. [asis,cPanel amp() WHM] cannot restore accounts for non-root resellers that use linked nodes. Because of this, “[_4]” will own this restored account instead.', $owner, 0 + @linked_node_types, \@linked_node_types, $new_owner ) );

        $cpuser_data->{'OWNER'} = $new_owner;
    }

    return;
}

sub _get_linkage_types ($username) {
    require Cpanel::LinkedNode::Worker::GetAll;
    require Cpanel::Config::LoadCpUserFile;

    my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load($username);

    return map { $_->{'worker_type'} } Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_hr);
}

sub _theme_is_valid_and_exists_or_default {
    my ($current_rs_value) = @_;

    my %defaults = Whostmgr::Packages::Info::get_defaults();
    my $defcpmod = $defaults{'cpmod'};

    return $defcpmod->{'default'} if ( !Cpanel::Themes::Available::is_theme_available($current_rs_value) );
    return $current_rs_value;
}

1;
