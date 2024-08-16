# cpanel - Cpanel/Elevate.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Elevate;

=head1 NAME

Cpanel::Elevate

=head1 SYNOPSIS

    my $elevate = Cpanel::Elevate->new(check_file => '/tmp/elevate-cpanel.json');
    my @output = $elevate->check();

See L<Cpanel::Security::Advisor::Assessors::Elevate> for a real use.

=head1 DESCRIPTION

Provide a standard interface for invoking the cPanel ELevate script, which
wraps the AlmaLinux ELevate project with logic designed to handle in-place
upgrades from CentOS 7 to AlmaLinux 8 with cPanel installed. For more
information on these projects, see L<https://go.cpanel.net/ELevate> and
L<https://almalinux.org/elevate>, respectively.

=cut

use Moo;

use cPstrict;

use Cpanel::SafeRun::Object ();
use Cpanel::Autodie         ();
use Cpanel::Exception       ();
use Cpanel::JSON            ();
use Cpanel::HTTP            ();
use Cpanel::HTTP::Client    ();

use Term::ANSIColor ();
use Scalar::Util    ();

use Try::Tiny;

=head1 CONSTRUCTOR

=head2 new(optional_property => value, ...)

Creates the object with (optional) specified properties.

=over

=item * manual_reboots

If true, invokes the script with C<--manual-reboots>, which suppresses
automatic reboots after stage completion.

=item * skip_cpanel_version_check

If true, invokes the script with C<--skip-cpanel-version-check>, which allows
outdated or development versions of cPanel to not incur a blocker.

=item * skip_elevate_version_check

If true, invokes the script with C<--skip-elevate-version-check>, which allows
non-release versions of the script to not incur a blocker.

=item * check_file

Specifies the file to which the script dumps blockers in JSON format when the
L<check> method is invoked. Defaults to C</var/cpanel/elevate-blockers>.

=item * update_to

Specifies which OS is the target of the upgrade. Defaults to C<almalinux>.

=item * ELEVATE_PATH

Specifies the path to the script. If the script cannot be run, it will be
fetched and saved to this location as well. Defaults to
C</usr/local/cpanel/scripts/elevate-cpanel>.

=item * ELEVATE_BASE_URL

Specifies the base URL from which to check for new versions and fetch the
script. If a value is provided, it is expected to end with a trailing slash
character. Defaults to L<https://raw.githubusercontent.com/cpanel/elevate/release>.

=item * ELEVATE_NOC_RECOMMENDATIONS_FILE

Specifies which file path will be used by L<noc_recommendations>.
Defaults to C</var/cpanel/elevate-noc-recommendations>.

=back

=cut

my %DEFAULTS = (
    'manual_reboots'                   => 0,
    'skip_cpanel_version_check'        => 0,
    'skip_elevate_version_check'       => 0,
    'check_file'                       => '/var/cpanel/elevate-blockers',
    'upgrade_to'                       => 'almalinux',
    'ELEVATE_PATH'                     => '/usr/local/cpanel/scripts/elevate-cpanel',
    'ELEVATE_BASE_URL'                 => 'https://raw.githubusercontent.com/cpanel/elevate/release',
    'ELEVATE_NOC_RECOMMENDATIONS_FILE' => '/var/cpanel/elevate-noc-recommendations',
);

has 'manual_reboots'                   => ( is => 'ro', default => $DEFAULTS{'manual_reboots'} );
has 'skip_cpanel_version_check'        => ( is => 'ro', default => $DEFAULTS{'skip_cpanel_version_check'} );
has 'skip_elevate_version_check'       => ( is => 'ro', default => $DEFAULTS{'skip_elevate_version_check'} );
has 'check_file'                       => ( is => 'ro', default => $DEFAULTS{'check_file'} );
has 'upgrade_to'                       => ( is => 'ro', default => $DEFAULTS{'upgrade_to'} );
has 'ELEVATE_PATH'                     => ( is => 'ro', default => $DEFAULTS{'ELEVATE_PATH'} );
has 'ELEVATE_BASE_URL'                 => ( is => 'ro', default => $DEFAULTS{'ELEVATE_BASE_URL'} );
has 'ELEVATE_NOC_RECOMMENDATIONS_FILE' => ( is => 'ro', default => $DEFAULTS{'ELEVATE_NOC_RECOMMENDATIONS_FILE'} );

has 'latest_version' => ( is => 'ro', lazy => 1, builder => \&_latest_version );

=head1 METHODS

=cut

=head2 $obj->version()

Obtains the version of the script pointed to by this object. If the script does
not have a version, returns 0.

=cut

sub version ($self) {

    my @args = ('--version');

    my $elevate_sro = $self->exec(
        'args' => \@args,
    );
    my $output = $elevate_sro->stdout;

    # if the foreach falls through, only an integer is printed, which is the version:
    return $output ? int $output : 0;
}

sub _latest_version ($self) {
    my $http     = Cpanel::HTTP::Client->new->die_on_http_error();
    my $url      = $self->ELEVATE_BASE_URL;
    my $response = $http->get( $url . '/version' );
    return int $response->content();
}

=head2 $obj->update()

Calls C<--update>, unless the script does not support this,
in which case, it will fetch a new copy itself.

Dies if an unrecoverable error occurred during this process.

=cut

sub update ($self) {

    my $current_version = $self->version;
    my $msg             = 'No details available.';

    # If we are able to get the version, then the self-update method will work
    # Otherwise, they have an old or non-function version which necessitates a download
    if ( defined $current_version && $current_version > 0 ) {

        my $elevate_sro = $self->exec(
            'args' => ['--update'],
        );
        $msg = $elevate_sro->stdout();
    }
    else {
        $self->_fetch();
    }

    # If we still can't get the version, something went wrong
    $current_version = $self->version;
    if ( !defined $current_version || $current_version < 1 ) {
        die Cpanel::Exception->create_raw( "Update of " . $self->ELEVATE_PATH . " failed:\n$msg" );
    }

    return;
}

=head2 $obj->check()

Runs a non-destructive check to list all conditions which would block the start
of the upgrade process. Returns the output of the script as a list of lines.
Use L<dump_blocker_file> after running this to obtain a machine-readable list
of blockers.

=cut

sub check ($self) {
    my @args = $self->_generate_standard_args();
    push @args, '--check', $self->check_file if $self->check_file ne $DEFAULTS{'check_file'};

    my $elevate_sro = $self->exec(
        'args' => \@args,
    );
    my $output = Term::ANSIColor::colorstrip( $elevate_sro->stdout() );

    return split( '\n', $output );
}

=head2 $obj->exec(args => [...], ...)

Runs the script via L<Cpanel::SafeRun::Object>. If the script cannot be run,
downloads the script and retries the command once more. Returns the SafeRun
object which results.

=cut

sub exec ( $self, %saferun_args ) {
    my $saferun_obj;
    my $tried_fetch = 0;

    {
        $saferun_obj = Cpanel::SafeRun::Object->new(
            'program' => $self->ELEVATE_PATH,
            %saferun_args,
            'before_exec' => sub {
                $ENV{'ELEVATE_BASE_URL'} = $self->ELEVATE_BASE_URL unless $DEFAULTS{'ELEVATE_BASE_URL'} eq $self->ELEVATE_BASE_URL;
                return;
            },
        );

        # If the problem was with the exec(), (re-)fetch the program and try again:
        if ( !$tried_fetch && $saferun_obj->exec_failed() ) {
            $tried_fetch = 1;
            $self->_fetch();
            redo;
        }
    }

    return $saferun_obj;
}

=head2 $obj->exec_or_die(...)

Convenience method which invokes C<die_if_error> on the results from L<exec>.

=cut

sub exec_or_die ( $self, %saferun_args ) {
    return $self->exec(%saferun_args)->die_if_error();
}

sub _fetch ($self) {
    Cpanel::HTTP::download_to_file( $self->ELEVATE_BASE_URL . '/elevate-cpanel', $self->ELEVATE_PATH );
    Cpanel::Autodie::chown( 0, 0, $self->ELEVATE_PATH );
    Cpanel::Autodie::chmod( 0700, $self->ELEVATE_PATH );

    return;
}

=head2 $obj->dump_blocker_file

Returns the contents of C<check_file> as a hashref, or undef if the file is
missing or empty. In case of (other) errors, throws exceptions like C<LoadFile()>
from L<Cpanel::Elevate>.

=cut

sub dump_blocker_file ($self) {
    return try {
        Cpanel::JSON::LoadFile( $self->check_file );
    }
    catch {
        my $ex = $_;

        require Scalar::Util;

        # return undef if the file is missing or empty
        !Scalar::Util::blessed($ex) && $ex =~ m/is empty|No such file or directory/
          ? undef
          : die $ex;
    };
}

sub _generate_standard_args ($self) {
    my @args;

    # boolean flags or flags with optional values
    foreach my $property (qw(skip_cpanel_version_check skip_elevate_version_check manual_reboots)) {
        die Cpanel::Exception::create( 'MissingMethod', [ method => $property, pkg => __PACKAGE__ ] ) unless $self->can($property);
        next                                                                                          unless $self->can($property)->($self);
        my $flag = $property =~ tr/_/\-/r;
        push @args, "--$flag";
    }

    # flags with required values
    foreach my $property (qw(upgrade_to)) {
        die Cpanel::Exception::create( 'MissingMethod', [ method => $property, pkg => __PACKAGE__ ] ) unless $self->can($property);
        my $value = $self->can($property)->($self);
        next unless defined $value && defined $DEFAULTS{$property};
        next if $value eq $DEFAULTS{$property};
        my $flag = $property =~ tr/_/\-/r;
        push @args, "--$flag=$value";
    }

    return @args;
}

=head2 $obj->noc_recommendations()

Returns a true value if an interested party has created the file at the location specified by C<ELEVATE_NOC_RECOMMENDATIONS_FILE> on the system, and a false value
otherwise. In particular, this true value will be the contents of the file, or a default message if the file is empty.

=cut

sub noc_recommendations ($self) {

    # TODO: make this a proper externally-visible constant somewhere
    my $default_msg = <<~EOS;
    Your server provider has requested that you contact their technical support
    for additional information before you continue with this upgrade process.
    EOS

    my $msg = "";
    try {
        local $/;
        Cpanel::Autodie::open( my $fh, '<', $self->ELEVATE_NOC_RECOMMENDATIONS_FILE );
        $msg = <$fh> || $default_msg;
        Cpanel::Autodie::close($fh);
    }
    catch {
        my $ex = $_;

        # Re-throw if Cpanel::Autodie didn't directly generate the exception:
        die $ex unless Scalar::Util::blessed($ex) && $ex->isa('Cpanel::Exception::ErrnoBase');

        # Use default if the error is something other than the file not existing:
        $msg = $default_msg unless $ex->error_name eq 'ENOENT';
    };

    return $msg;
}

1;

__END__

=head1 TODO

=over

=item * Ideally, methods named after the command line flag they implement should be available for the other flags, like C<--start>, C<--continue>, etc.

=back
