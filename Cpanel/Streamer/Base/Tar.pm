package Cpanel::Streamer::Base::Tar;

# cpanel - Cpanel/Streamer/Base/Tar.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::Base::Tar

=head1 DESCRIPTION

A base class streamer module for streaming L<tar(1)>.

=head1 COMMON PATTERNS

The following pertain to all (or, “both”, as of this writing!) subclasses:

=head2 Parameters

C<new()> takes a list of key/value pairs. Subclasses may recognize
more, but these are what all subclasses recognize:

=over

=item * C<directory> - The directory into which to restore contents.

=item * C<setuid_username> - The name of the user as whom
the archive will be restored. Required if run as root; forbidden otherwise.

=item * C<transform> - Optional, a value to give to tar’s C<--transform>
parameter.

=back

Individual subclasses may stipulate additional parameter requirements.

=head2 ERRORS

If the child process fails prior to executing C<tar>,
the process will end with the exit code stored in this module’s
C<PRE_EXEC_EXIT_CODE()> constant.

=head1 SUBCLASS INTERFACE

Subclasses can/must define the following methods:

=over

=item * C<_tar_parameters( \%OPTS )> - (required) %OPTS are the parameters
given to C<new()>. Returns a list of parameters to give to C<tar>. Runs
after the setuid operation.

=item * C<_prepare_std_filehandles( $SOCKET )> - (required) Configures
the child process’s STDIN, STDOUT, and STDERR prior to the C<exec()>.
Could also be (ab)used for other needed prep?

=item * C<_REQUIRED_PARAMETERS()> (optional) Stipulates additional
parameter requirements to C<new()>.

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Streamer';

use Cpanel::Streamer::ReportUtil ();
use Cpanel::Tar                  ();

# default implementation
use constant _REQUIRED_PARAMETERS => ();

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 PRE_EXEC_EXIT_CODE

A “magic number” process exit code that indicates that the subprocess
did not actually run C<tar>. This can happen either if the C<exec()> failed
or if an error happened prior thereto.

=cut

use constant PRE_EXEC_EXIT_CODE => 197;

#----------------------------------------------------------------------

sub _init ( $self, %opts ) {
    my @req = (
        'directory',
        $self->_REQUIRED_PARAMETERS(),
    );
    push @req, 'setuid_username' if !$>;

    my @missing = grep { !$opts{$_} } sort @req;
    die "Need: @missing" if @missing;

    my $directory = $opts{'directory'};

    my $tar_cfg = Cpanel::Tar->load_tarcfg();

    my $tar_bin = $tar_cfg->{'bin'} or die 'Failed to find tar binary!';

    my $setuid_username = $opts{'setuid_username'};
    die 'Cannot setuid as user!' if $> && $setuid_username;

    Cpanel::Streamer::ReportUtil::start_reporter_child(
        streamer => $self,

        get_exit_code_for_error => \&PRE_EXEC_EXIT_CODE,

        todo_cr => sub ($child_s) {
            if ($setuid_username) {
                require Cpanel::AccessIds::SetUids;
                Cpanel::AccessIds::SetUids::setuids($setuid_username);
            }

            # This is better than tar’s --directory parameter because
            # we’ll get a more meaningful error.
            chdir $directory or die "PID $$: chdir($directory) as EUID $>: $!";

            $self->_prepare_std_filehandles($child_s);

            exec {$tar_bin} (
                $tar_bin,
                Cpanel::Tar::OPTIMIZATION_OPTIONS(),
                _base_tar_parameters( \%opts ),
                $self->_tar_parameters( \%opts ),
            ) or die "exec($tar_bin) as EUID $>: $!";
        },
    );

    return;
}

sub _base_tar_parameters ($opts_hr) {
    my $xform = $opts_hr->{'transform'};

    return (
        ( $xform ? ( '--transform' => $xform ) : () ),
    );
}

1;
