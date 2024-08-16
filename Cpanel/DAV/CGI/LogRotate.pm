
# cpanel - Cpanel/DAV/CGI/LogRotate.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DAV::CGI::LogRotate;

use strict;
use warnings;
use Cpanel::Fcntl::Constants ();
use Cpanel::Binaries         ();
use Cpanel::Logger           ();
use Cpanel::PwCache          ();
use Cpanel::SafeRun::Object  ();
use Cpanel::Server::Utils    ();    # needed by Cpanel::Logger

=head1 NAME

Cpanel::DAV::CGI::LogRotate

=head1 SYNOPSIS

  my $lr = Cpanel::DAV::CGI::LogRotate->new(
    basedir_relative => 'application/log',
    log_pattern => "*.log",
    min_size_k => 512,
    max_size_k => 10240,
  );

  $lr->run;

=head1 DESCRIPTION

This module is a log rotation wrapper for per-user processes launched by
Cpanel::DAV::CGI.

The module avoids launching C<logrotate> on every request by using a lock
that ensures it can only be launched once per hour at most. Once the
C<logrotate> utility is launched, its own criteria also apply.

It is only suitable for rotating log files owned by individual cPanel users.

=head1 CONSTRUCTOR

=head2 new()

=head3 ARGUMENTS

=over

=item * basedir_relative - The directory in which the application's log files are kept, relative to the user's home directory.

=item * log_pattern - The pattern to use when looking for log files, using a C<logrotate>-compatible glob pattern.

=item * min_size_k - The log size in kilobytes (without any unit suffix) required to trigger log rotation.

=item * max_size_k - The log size in kilobytes (without any unit suffix) at which log rotation will occur even if the a day has not elapsed yet.

=back

=cut

sub new {
    my ( $package, %opts ) = @_;
    die 'need basedir_relative' if !$opts{basedir_relative};
    die 'need log_pattern'      if !$opts{log_pattern};
    die 'need min_size_k'       if !$opts{min_size_k};
    die 'need max_size_k'       if !$opts{max_size_k};

    $opts{homedir} = Cpanel::PwCache::gethomedir();
    $opts{logger}  = Cpanel::Logger->new();
    Cpanel::Server::Utils::is_subprocess_of_cpsrvd();    # silence cplint

    return bless \%opts, $package;
}

=head1 METHODS

=head2 run()

Perform log rotation if appropriate (based on the criteria specified on construction).

This is the only instance method you should normally have to call directly.

=cut

sub run {
    my ($self) = @_;
    my $logrotate_bin = Cpanel::Binaries::path('logrotate');
    if ( !-x $logrotate_bin ) {
        $self->{logger}->info('logrotate binary was not found');
        return;
    }
    if ( $self->try_exclusion_file ) {
        my $lr_conf = sprintf( '%s/%s/logrotate.conf', $self->{homedir}, $self->{basedir_relative} );
        my $fh;
        if ( sysopen( $fh, $lr_conf, $Cpanel::Fcntl::Constants::O_EXCL | $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT, 0600 ) ) {

            # If necessary, logrotate.conf can be manually edited after creation (for example, to enable compression), and those edits will be preserved.
            $self->{logger}->info('logrotate.conf does not exist yet; creating ...');
            syswrite $fh, $self->lr_conf_text;
            close $fh;
        }

        Cpanel::SafeRun::Object->new(
            program => $logrotate_bin,
            args    => [ '-s', sprintf( '%s/%s/logrotate.state', $self->{homedir}, $self->{basedir_relative} ), $lr_conf ],
            timeout => 600,
        );
    }

    return;
}

=head2 lr_conf_text()

Returns the text of a C<logrotate> configuration file for this instance.

=cut

sub lr_conf_text {
    my ($self) = @_;

    local $SIG{__WARN__} = sub { die 'Problem generating logrotate conf: ' . shift() };
    return <<EOF;
$self->{homedir}/$self->{basedir_relative}/$self->{log_pattern} {
\tminsize $self->{min_size_k}k
\tmaxsize $self->{max_size_k}k
\tdaily
\trotate 9
}
EOF
}

=head2 try_exclusion_file()

Attempt to acquire the exclusive lock on today's rotation attempt.

Returns true if this instance is responsible for today's rotation.

=cut

sub try_exclusion_file {
    my ($self) = @_;

    # Prevent race conditions by ensuring that any stale exclusion file being expired could never be either the current one or the next one.
    # 23 % 3 is 2, so this rolls over cleanly to 0 when the hour does instead of doubling or skipping.
    my $hour             = _get_hour();
    my $hour_suffix      = $hour % 3;
    my $prev_hour_suffix = ( $hour - 1 ) % 3;

    my $current_exclusion_file = sprintf( '%s/%s/%s.%s', $self->{homedir}, $self->{basedir_relative}, 'logrotate.excl', $hour_suffix );
    my $prev_exclusion_file    = sprintf( '%s/%s/%s.%s', $self->{homedir}, $self->{basedir_relative}, 'logrotate.excl', $prev_hour_suffix );
    unlink $prev_exclusion_file;

    my $fh;
    if ( sysopen( $fh, $current_exclusion_file, $Cpanel::Fcntl::Constants::O_EXCL | $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT, 0600 ) ) {
        close $fh;
        return 1;
    }

    return 0;
}

sub _get_hour {
    return ( ( gmtime time )[2] );
}

=head1 NAMESPACE

This is currently under Cpanel::DAV::CGI because that's where it's needed,
but it could possibly be generic enough to move higher up.

=cut

1;
