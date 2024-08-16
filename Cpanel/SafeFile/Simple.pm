package Cpanel::SafeFile::Simple;

# cpanel - Cpanel/SafeFile/Simple.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

use Cpanel::Debug     ();
use Cpanel::TimeHiRes ();
use Cpanel::LoadFile  ();
use Cpanel::Fcntl     ();

my $DEFAULT_MAX_ATTEMPTS = 120;

sub new {
    my ( $class, $file, %OPTS ) = @_;

    if ( my $lock = create_lock( $file, %OPTS ) ) {
        return bless { 'lock' => $lock }, $class;
    }

    return;
}

sub create_lock {
    my ( $file, %OPTS ) = @_;

    $OPTS{'max_attempts'} ||= $DEFAULT_MAX_ATTEMPTS;

    # case CPANEL-3992:
    # One attempt used to be a one second wait. In order to reduce
    # the wait times when we have lots of cron jobs running at the same
    # time the time between checks has been reduced to 0.250 seconds.
    # To keep the original timeframe for max_attempts, we need to multiple
    # by 4
    $OPTS{'max_attempts'} *= 4;

    my $flags = Cpanel::Fcntl::or_flags(qw( O_WRONLY O_EXCL O_CREAT ));

    my $attempts = 0;
    my $lock_fh;
    my $open_ok = 0;
    my $pid;
    my $pidinfo;

    # if something else gets a lock for $file right at this point this sysopen will fail
    while (1) {
        $open_ok = sysopen( $lock_fh, $file, $flags, 0600 );

        last if $open_ok || ++$attempts >= $OPTS{'max_attempts'};

        ( $pid, $pidinfo ) = split( m/\n/, Cpanel::LoadFile::loadfile( $file, { 'skip_exists_check' => 1 } ), 2 );

        if ( defined $pid && kill( 0, $pid ) == 0 ) {
            Cpanel::Debug::log_warn("lock file $file created by pid $pid was not removed before the process died.");
            return $file;
        }

        Cpanel::TimeHiRes::sleep(0.250);
    }

    if ($open_ok) {
        print {$lock_fh} "$$\n$0\n";
        close($lock_fh);
        return $file;
    }

    $pidinfo ||= Cpanel::LoadFile::loadfile("/proc/$pid/cmdline");
    $pidinfo =~ s/\0/ /g  if defined $pidinfo;
    $pidinfo =~ s/\s+$//g if defined $pidinfo;

    Cpanel::Debug::log_warn("attempt lock file $file timed out after $OPTS{'max_attempts'} attempts; lock still held by pid $pid ($pidinfo).");

    return;
}

sub unlock {
    my ($self) = @_;
    return unlink( $self->{'lock'} );
}

1;
