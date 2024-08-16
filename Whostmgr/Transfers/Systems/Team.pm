package Whostmgr::Transfers::Systems::Team;

# cpanel - Whostmgr/Transfers/Systems/Team.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::Autodie            ();
use Cpanel::FileUtils::Write   ();
use Cpanel::LoadFile::ReadFast ();
use Cpanel::Team::Config       ();
use Cpanel::Team::Constants    ();

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::Team

=head1 SYNOPSIS

N/A. This module is used as part of the Transfer/Restore system.
See Whostmgr::Transfers::System and Whostmgr::Transfers::AccountRestoration

=head1 DESCRIPTION

This module is a component of the Transfer/Restoration system for accounts.
It should probably not be called directly except for testing.

This component module detects if the account being transferred/restored has
team file in the SOURCE archive and makes sure they are carried over when the
transfer/restore completes.

=head1 FUNCTIONS


=cut

=head2 get_prereq()

This function returns an arrayref of Transfer/Restore system component
names that should be called before this module in execution of the
Transfer/Restore.

=head3 Arguments

None.

=head3 Returns

This function returns an arrayref of prerequisite components.

=head3 Exceptions

None.

=cut

sub get_prereq {
    return ['Account'];
}

=head2 get_phase()

This function returns the 'phase' this Transfer/Restore component should
be executed during. Please note that any prerequisite modules must be in
or before this phases!

=head3 Arguments

None.

=head3 Returns

The numeric 'phase'.

=head3 Exceptions

None.

=cut

sub get_phase {
    return 120;
}

=head2 get_summary()

This function returns an arrayref of localized descriptions for
this Transfer/Restore component.

=head3 Arguments

None.

=head3 Returns

An arrayref of localized strings.

=head3 Exceptions

Anything maketext can throw.

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext("This module will restore the team configuration file.") ];
}

=head2 get_restricted_available()

This function is used to inform the Transfer/Restore system that
this component supports restricted restoration.

=head3 Arguments

None.

=head3 Returns

This function returns 1.

=head3 Exceptions

None.

=cut

sub get_restricted_available {
    return 1;
}

=head2 unrestricted_restore()

This class method is the workhorse of the module. This function is used
by the Transfer/Restore system to suspend the user if suspended on SOURCE.

Please note that the 'unrestricted_restore' method is meant to be used
with the unrestricted type of restoration. But, this component should be
safe to run in both restricted and unrestricted mode.

=head3 Arguments

None.

=head3 Returns

This function returns 1 on success and failure, but the failure will trigger
a warning.

=head3 Exceptions

Anything the archive manager can throw.
Anything maketext can throw.

=cut

sub unrestricted_restore {
    my ($self) = @_;

    my $old_team_owner = $self->olduser();
    my $new_team_owner = $self->newuser();
    my $extract_dir    = $self->extractdir();

    my $team_file = "$extract_dir/team/$old_team_owner";
    my ( $uid, $team_owner_gid, $user_homedir ) = ( $self->{'_utils'}->pwnam() )[ 2, 3, 7 ];

    if ( !-e $team_file ) {
        $self->start_action( $self->_locale()->maketext( 'The user “[_1]” does not have a team configuration file. The system will not create the team file for the restored user.', $new_team_owner ) );
        return 1;
    }
    my $new_team_file = "$Cpanel::Team::Constants::TEAM_CONFIG_DIR/$new_team_owner";
    Cpanel::Autodie::mkdir_if_not_exists( $Cpanel::Team::Constants::TEAM_CONFIG_DIR, 0755 );
    if ( open my $FH, "<", $team_file ) {
        my ( $ok, $err ) = $self->_validate_team_config( $team_file, $FH );
        if ( !$ok ) {
            $self->warn($err);
            $self->start_action( $self->_locale()->maketext( 'The system will not create the team configuration file for the restored user “[_1]”.', $new_team_owner ) );
            return 1;
        }
        seek $FH, 0, 0;
        ( $ok, $err ) = $self->_write_team_file( $new_team_file, $FH );
        if ( !$ok ) {
            $self->warn($err);
            return 1;
        }
    }
    elsif ( $! != _ENOENT() ) {
        $self->warn("open($new_team_file): $!");
    }

    Cpanel::Autodie::chmod( 0640, $new_team_file );
    Cpanel::Autodie::chown( 0, $team_owner_gid, $new_team_file );
    $self->start_action( $self->_locale()->maketext( 'The Team configuration file for “[_1]” has been restored successfully.', $new_team_owner ) );

    return 1;
}

sub _write_team_file {
    my ( $self, $path, $contents_fh ) = @_;

    my $new_team_owner   = $self->newuser();
    my $old_team_owner   = $self->olduser();
    my $team_config_data = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $contents_fh, $team_config_data );
    $team_config_data =~ s/$old_team_owner/$new_team_owner/ if $old_team_owner ne $new_team_owner;
    Cpanel::FileUtils::Write::overwrite_no_exceptions( $path, $team_config_data, "0640" ) or do {
        return ( 0, $self->_locale()->maketext( 'The system failed to write the file “[_1]” because of an error: [_2]', $path, $! ) );
    };

    return 1;
}

sub _validate_team_config {
    my ( $self, $file, $FH ) = @_;
    my $old_team_owner = $self->olduser();

    chomp( my @config = <$FH> );
    my $header = shift @config;                   # Fetching the team owner
    my ($team_owner) = split( /\s+/, $header );
    if ( $team_owner ne $old_team_owner ) {
        return ( 0, $self->_locale()->maketext( 'The team owner name “[_1]” has been modified to “[_2]”.', $old_team_owner, $team_owner ) );
    }

    eval { Cpanel::Team::Config::validate_config_fields( \@config, $file ); };
    return ( 0, $self->_locale()->maketext( 'The team config file “[_1]” is corrupt.', $file ) ) if $@;
    return 1;

}
*restricted_restore = \&unrestricted_restore;

1;
