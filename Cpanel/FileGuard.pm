package Cpanel::FileGuard;

# cpanel - Cpanel/FileGuard.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#be lean --
use strict;
use Cpanel::Destruct ();
use Cpanel::SafeFile ();

sub new {
    my ( $class, $filename ) = @_;

    die "Missing filename to lock.\n" unless defined $filename;

    local $Cpanel::SafeFile::MAX_FLOCK_WAIT = 86400;    # wait up to one day for the flock
    local $Cpanel::SafeFile::LOCK_WAIT_TIME = 86400;    # wait up to one day for the dotlock

    my $lock = Cpanel::SafeFile::safelock($filename);
    die "Failed to lock $filename.\n" unless defined $lock;

    my %obj = (
        'file' => $filename,
        'lock' => $lock,
        'pid'  => $$,
    );

    bless \%obj, $class;

    return \%obj;
}

sub file {
    my ($self) = @_;
    return $self->{'file'};
}

sub lockfile {
    my ($self) = @_;
    return $self->{'lock'}->get_path();
}

sub _lockfh {
    my ($self) = @_;
    return $self->{'lock'}->get_filehandle();
}

sub close {
    my ($self) = @_;

    if ( defined $self->{'lock'} && $self->{'pid'} == $$ ) {
        if ( my $unlock = Cpanel::SafeFile::safeunlock( $self->{'lock'} ) ) {
            $self->{'lock'} = undef;
            return $unlock;
        }
    }

    return 0;
}

sub DESTROY {
    my ($self) = @_;

    return if Cpanel::Destruct::in_dangerous_global_destruction();

    return if $self->{'pid'} != $$ || !defined $self->{'lock'};

    return $self->close();
}

1;
