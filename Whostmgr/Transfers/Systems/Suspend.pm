package Whostmgr::Transfers::Systems::Suspend;

# cpanel - Whostmgr/Transfers/Systems/Suspend.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw(
  Whostmgr::Transfers::Systems
);

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::LoadFile               ();
use Cpanel::SafeRun::Object        ();
use Cpanel::Shell                  ();

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::Suspend

=head1 SYNOPSIS

N/A. This module is used as part of the Transfer/Restore system.
See Whostmgr::Transfers::System and Whostmgr::Transfers::AccountRestoration

=head1 DESCRIPTION

This module is a component of the Transfer/Restoration system for accounts.
It should probably not be called directly except for testing.

This component module detects if the account being transferred/restored was
suspended in the SOURCE archive and makes sure they are suspended when the
transfer/restore completes.

=head1 FUNCTIONS


=cut

=head2 get_prereq()

This function returns an arrayref of Transfer/Restore system component
names that should be called before this module in execution of the
Transfer/Restore. It should be noted that the specified prerequisite
component must be in or before the module's 'phase' as of 2/5/18

=head3 Arguments

None.

=head3 Returns

This function returns an arrayref of prerequisite components.

=head3 Exceptions

None.

=cut

sub get_prereq {
    return ['BandwidthData'];
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
    return 110;
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
    return [ $self->_locale()->maketext('This module will suspend the restored user if they were suspended at the source.') ];
}

=head2 get_restricted_summary()

This function returns an arrayref of localized descriptions for
this Transfer/Restore component's Restricted Restore path.

=head3 Arguments

None.

=head3 Returns

An arrayref of localized strings.

=head3 Exceptions

Anything maketext can throw.

=cut

sub get_restricted_summary {
    my ($self) = @_;

    return [ $self->_locale()->maketext('The system will not restore the suspension reason or old shell for the account and instead will use a default.') ];
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

This function returns 1 on success and a two-part array return of
( 0, $error ) when the function fails.

=head3 Exceptions

Anything the archive manager can throw.
Anything maketext can throw.

=cut

sub unrestricted_restore {
    my ($self) = @_;

    my $olduser     = $self->olduser();
    my $newuser     = $self->newuser();
    my $extract_dir = $self->extractdir();

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile($newuser);

    if ( !$cpuser_ref->{'SUSPENDED'} ) {
        $self->start_action( $self->_locale()->maketext( 'The user “[_1]” was not suspended. The system will not suspend the restored user.', $newuser ) );
        return 1;
    }

    $self->start_action( $self->_locale()->maketext( 'The user “[_1]” was suspended. The system will now attempt to suspend the restored user.', $newuser ) );

    my $reason = $self->get_reason( $extract_dir, $olduser ) || 'Transfer/Restore';
    my $locked = $self->has_reseller_lock( $extract_dir, $olduser );

    my $suspendinfo_hr = $self->_get_parsed_suspendinfo();

    my $leave_ftp_yn = $suspendinfo_hr && $suspendinfo_hr->{'leave-ftp-accts-enabled'};

    # TODO: once we split up suspend account, only re-suspend the parts we need to
    my $run = Cpanel::SafeRun::Object->new(
        'program' => '/usr/local/cpanel/scripts/suspendacct',
        'args'    => [
            ( $leave_ftp_yn ? '--leave-ftp-accts-enabled' : () ),
            '--',
            $newuser,
            $reason,
            $locked,
        ],
    );

    $self->out( scalar $run->stdout() );

    if ( $run->CHILD_ERROR() ) {
        my $err = $self->_locale()->maketext( '“[_1]” returned an error: [_2]', '/usr/local/cpanel/scripts/suspendacct', $run->autopsy() . $run->stderr() );
        return ( 0, $err );
    }

    my %suspendinfo;

    if ( my $old_shell = $self->get_old_shell($olduser) ) {
        $suspendinfo{'shell'} = $old_shell;
    }

    if ($leave_ftp_yn) {
        $suspendinfo{'leave-ftp-accts-enabled'} = 1;
    }

    if (%suspendinfo) {
        require Whostmgr::Accounts::SuspensionData::Writer;
        my $wtr = Whostmgr::Accounts::SuspensionData::Writer->new();
        $wtr->write_info( $newuser, \%suspendinfo );
    }

    return 1;
}

=head2 has_reseller_lock( $extract_dir, $olduser )

This class method determines if the specified user had a reseller lock
on their suspended account on SOURCE.

=head3 Arguments

=over 4

=item extract_dir    - SCALAR - The directory in which the archive was extracted.

=item olduser    - SCALAR - The name for the restored/transferred user in the archive.

=back

=head3 Returns

This class method returns 1 if the user had a reseller suspension lock on SOURCE.
It returns 0 if the user did not have a reseller suspension lock on SOURCE.

=head3 Exceptions

None.

=cut

sub has_reseller_lock {
    my ( $self, $extract_dir, $olduser ) = @_;

    return -e "$extract_dir/suspended/$olduser.lock" ? 1 : 0;
}

=head2 get_reason ( $extract_dir, $olduser )

This class method determines if the restoring/transferring user
had a suspension reason on SOURCE and returns it.

In restricted mode, this class method returns only nothing.

=head3 Arguments

=over 4

=item extract_dir    - SCALAR - The directory in which the archive was extracted.

=item olduser    - SCALAR - The name for the restored/transferred user in the archive.

=back

=head3 Returns

The class method returns a scalar that contains the reason, if one is found, otherwise
it returns nothing.

=head3 Exceptions

Anything that C<Cpanel::LoadFile::load_if_exists()> can return.

=cut

sub get_reason {
    my ( $self, $extract_dir, $olduser ) = @_;

    return if !$self->{'_utils'}->is_unrestricted_restore();

    my $reason = Cpanel::LoadFile::load_if_exists("$extract_dir/suspended/$olduser");

    #Empty file should prompt an undef return.
    return length($reason) ? $reason : undef;
}

=head2 get_old_shell( $extract_dir, $olduser )

This class method determines if the restoring/transferring user had a shell before
they were suspended and returns it.

In restricted mode, this class method returns only nothing.

=head3 Arguments

=over 4

=item extract_dir    - SCALAR - The directory in which the archive was extracted.

=item olduser    - SCALAR - The name for the restored/transferred user in the archive.

=back

=head3 Returns

This class method returns a scalar which contains the user's shell before suspension
on SOURCE. If there was no F<suspendinfo/$username> file in the archive, then
undef is returned.

=head3 Exceptions

Anything that C<Cpanel::LoadFile::load_if_exists()> can return.

=cut

sub get_old_shell {
    my ( $self, $olduser ) = @_;

    return if !$self->{'_utils'}->is_unrestricted_restore();

    my $suspendinfo_hr = $self->_get_parsed_suspendinfo();

    return if !$suspendinfo_hr;

    my $msg;

    if ( my $old_shell = $suspendinfo_hr->{'shell'} ) {
        if ( Cpanel::Shell::is_valid_shell($old_shell) ) {
            return $old_shell;
        }
        else {
            $msg = $self->_locale()->maketext( 'The account archive’s suspension data indicates the “[_1]” shell, but this system does not recognize that shell. The system will not save this information locally.', $old_shell );
        }
    }

    #We got here because there’s something wrong with what’s in the file.

    $msg ||= $self->_locale()->maketext( 'The file “[_1]” in the archive is corrupt.', "suspendinfo/$olduser" );

    $self->warn($msg);

    return;
}

sub _get_parsed_suspendinfo ($self) {
    my $olduser     = $self->olduser();
    my $extract_dir = $self->extractdir();

    my $path        = "$extract_dir/suspendinfo/$olduser";
    my $suspendinfo = Cpanel::LoadFile::load_if_exists($path);

    return $suspendinfo && do {
        require Whostmgr::Accounts::SuspensionData::Storage;
        Whostmgr::Accounts::SuspensionData::Storage::parse_info($suspendinfo);
    };
}

*restricted_restore = \&unrestricted_restore;

1;
