package Cpanel::SafeFile::FileLocker;

# cpanel - Cpanel/SafeFile/FileLocker.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

use Cpanel::SafeFile ();

=encoding utf-8

=head1 NAME

Cpanel::SafeFile::FileLocker - A Cpanel::StateFile::LockFile implemention

=head1 SYNOPSIS

    use Cpanel::SafeFile::FileLocker ();
    use Cpanel::LoggerAdapter ();
    my $logger;
    my $filelocker;
    BEGIN {
       $logger     = Cpanel::LoggerAdapter->new();
       $filelocker = Cpanel::SafeFile::FileLocker->new( { 'logger' => $logger } );
    }
    use Cpanel::StateFile ( '-filelock' => $filelocker, '-logger' => $logger );

=head1 DESCRIPTION

A thin shim around Cpanel::SafeFile for queueprocd

=cut

sub new {
    my ( $class, $args_hr ) = @_;
    $args_hr = {} unless defined $args_hr;
    die "Argument to new must be a hash reference, not “$args_hr”.\n" unless 'HASH' eq ref $args_hr;
    die "Required “logger” argument is missing.\n"                    unless exists $args_hr->{logger};
    return bless { 'logger' => $args_hr->{'logger'} }, $class;
}

=head2 file_lock

See Cpanel::StateFile::StateFile::file_lock

=cut

sub file_lock {
    my ( $self, $file ) = @_;

    my $lock_obj = Cpanel::SafeFile::safelock($file);

    $lock_obj or $self->{'logger'}->throw("Failed to lock $file as $> ($!)");
    return $lock_obj;
}

=head2 file_unlock

See Cpanel::StateFile::StateFile::file_unlock

=cut

sub file_unlock {
    my ( $self, $lock_obj ) = @_;

    if ( !Cpanel::SafeFile::safeunlock($lock_obj) ) {
        my $error = $!;
        my $filename;
        foreach my $method (qw{file get_path}) {
            my $sub = $lock_obj->can($method) or next;
            $filename = $sub->($lock_obj);
            last;
        }
        $filename //= 'unknown';

        my $msg = "Failed to unlock " . $filename . " ($error)";

        $self->{'logger'}->throw($msg);
    }
    return 1;

}

1;
