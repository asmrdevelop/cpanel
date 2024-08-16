package Cpanel::FileUtils::Flock;

# cpanel - Cpanel/FileUtils/Flock.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::Flock - BSD lock object w/ DESTROY

=head1 SYNOPSIS

    open my $wfh, '>', '/path/to/file' or die $!;

    Cpanel::FileUtils::Flock::flock( $wfh, 'EX', 'NB' ) or do {

        # We get here if and only if the flock() failed from EAGAIN.
    };

    undef $wfh;    #LOCK_UN will be called before Perl close()s $wfh

=head1 DESCRIPTION

This simple wrapper around C<flock()> ensures that we always LOCK_UN before
a Perl filehandle is reaped. This is important because otherwise the kernel
will clear out the lock automatically, which is great as a backup but is
quite slow.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Cpanel::Exception ();
use Cpanel::Fcntl     ();

use constant _EAGAIN => 11;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 flock( $FILEHANDLE, @FLAGS )

This takes a filehandle, runs Perl’s C<flock()> built-in on it, then
C<bless()>es the
filehandle. @FLAGS, for convenience, is a list of C<EX>, C<SH>, and/or C<NB>,
as per the usual invocations of Perl’s C<flock()> built-in.

In order to avoid inadvertent clobberage of other filehandle classes’
behavior, this will reject any filehandle that’s not a plain GLOB
or an instance of this class. In the latter case, the PID must match the
PID that acquired the lock initially.

On success, this returns the filehandle, newly B<bless()>ed.
If the C<flock()> fails, then usually a L<Cpanel::Exception::IO::FlockError>
is thrown, but if the failure is EAGAIN and the C<NB> flag was given, then
undef is returned.

=cut

sub flock {
    my ( $filehandle, @flags ) = @_;

    if ( 'GLOB' ne ref $filehandle ) {
        local $@;
        if ( !eval { $filehandle->isa(__PACKAGE__) } ) {
            die sprintf( "Filehandle “$filehandle” should be a plain GLOB or %s instance.", __PACKAGE__ );
        }

        my $old_pid = ${*$filehandle}{'_pid'};
        if ( $$ != $old_pid ) {
            die "$filehandle was locked in process $old_pid; can’t relock from process $$.";
        }
    }

    substr( $_, 0, 0 ) = 'LOCK_' for @flags;

    my $operation = Cpanel::Fcntl::or_flags(@flags);

    local ( $!, $^E );
    CORE::flock( $filehandle, $operation ) or do {
        my $err = $!;

        if ( $err == _EAGAIN() && $operation & Cpanel::Fcntl::or_flags('LOCK_NB') ) {
            return !!undef;
        }

        #Try to get the path from /proc.
        my $path = fileno $filehandle;
        $path &&= readlink "/proc/$$/fd/$path";

        die Cpanel::Exception::create( 'IO::FlockError', [ path => $path, error => $err, operation => $operation ] );
    };

    bless $filehandle, __PACKAGE__;

    ${*$filehandle}{'_pid'} = $$;

    return $filehandle;
}

sub DESTROY {
    my ($self) = @_;

    if ( ${*$self}{'_pid'} == $$ ) {
        local ( $!, $^E );

        CORE::flock( $self, $Cpanel::Fcntl::Constants::LOCK_UN ) or do {

            #If there’s no fileno() return, then we probably close()d already.
            if ( my $fileno = fileno($self) ) {
                warn "unlock(fd $fileno): $!";
            }
        };

        $self->SUPER::DESTROY();
    }

    return;
}

1;
