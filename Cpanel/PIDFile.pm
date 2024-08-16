package Cpanel::PIDFile;

# cpanel - Cpanel/PIDFile.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::PIDFile - simple, race-safe PID files

=head1 SYNOPSIS

    use Cpanel::PIDFile ();

    my $pid_file = '/path/to/pid/file';

    #Will throw a Cpanel::Exception::CommandAlreadyRunning
    #if $pid_file already exists.
    Cpanel::PIDFile->do(
        $pid_file,
        sub { #Do interesting things … },
    }

    my $pid = Cpanel::PIDFile->get_pid($pid_file);

=head1 DESCRIPTION

This creates race-safe, signal-safe PID files that will live only during
the lifetime of the passed code reference.

=head1 IMPLEMENTATION DETAILS

Rather than creating normal files to store a PID, this creates symlinks
whose destinations contain that information. These are, by definition,
“dangling” symlinks; however, that’s by design here. We thus alleviate
the need to open or to read any files directly. And, since the C<symlink()>
system call will error out if the path already exists, we avoid race
safety issues as well.

=cut

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Autodie       ();
use Cpanel::Exception     ();
use Cpanel::Rand::Path    ();
use Cpanel::Signal::Defer ();

sub do {
    my ( $class, $pid_file, $todo_cr ) = @_;

    die 'Need PID file!' if !length $pid_file;

    #Ensure that the PID file gets cleaned up even if a signal comes in.
    my @signals = @{ Cpanel::Signal::Defer::NORMALLY_DEFERRED_SIGNALS() };

    my %old_sig = map { $_ => $SIG{$_} } @signals;

    my $euid = $>;

    my $on_signal_cr = sub {
        my ($sig) = @_;

        {
            local ( $!, $^E );
            local $> = $euid;

            if ( $> == $euid ) {
                unlink $pid_file or do {
                    if ( !$!{'ENOENT'} ) {
                        warn "Failed to unlink “$pid_file”: $!";
                    }
                };
            }
            else {
                warn "Skipping unlink($pid_file) because EUID is $>, not the original $euid, and we failed to set it back: $!";
            }
        }

        #no “local” because anything that would have local()ed
        #this value is already still protecting the global value.
        $SIG{$sig} = $old_sig{$sig} || 'DEFAULT';

        kill( $sig, $$ );    #now resend the signal
    };

    local @SIG{@signals} = ($on_signal_cr) x @signals;

    my $pid = $class->new($pid_file);

    return $todo_cr->();
}

#----------------------------------------------------------------------
#Methods below deal with the mechanics of the PID file itself.

#Class method
sub get_pid {
    my ( $class, $pidfile_path ) = @_;

    my $dest;
    try {
        $dest = Cpanel::Autodie::readlink($pidfile_path);
    }
    catch {
        if ( !try { $_->error_name() eq 'ENOENT' } ) {
            local $@ = $_;
            die;
        }
    };

    my $prefix = $class->_prefix();

    if ( defined $dest ) {
        $dest =~ s<\A\Q$prefix\E><> or do {
            die Cpanel::Exception->create_raw("Unparsable symlink destination: “$pidfile_path” -> “$dest”");
        };
    }

    return $dest;
}

#There’s probably not much reason to instantiate this class directly.
#If you can use do() above, then you’ll get signal handling.
sub new {
    my ( $class, $path ) = @_;

    my $symlink_target = $class->_prefix() . $$;

    try {
        Cpanel::Autodie::symlink( $symlink_target, $path );
    }
    catch {
        if ( try { $_->error_name() eq 'EEXIST' } ) {
            my $pid = $class->get_pid($path);

            #If the process is still running, then die().
            if ( $pid && kill( 0, $pid ) ) {
                die Cpanel::Exception::create( 'CommandAlreadyRunning', [ pid => $pid ] );
            }

            #Process is dead? Great: replace the old symlink, and move on.
            _replace_pidfile_or_die( $path, $symlink_target );
        }
        else {
            local $@ = $_;
            die;
        }
    };

    return bless { _pid => $$, _euid => $>, _path => $path }, $class;
}

sub _replace_pidfile_or_die {
    my ( $path, $symlink_target ) = @_;

    #This avoids unlink()-then-symlink() because we want better
    #race safety. rename() will atomically clobber an existing symlink,
    #which is what we want: there is thus no opportunity for anything
    #to create $path after unlink() but before symlink().

    my $tmpfile = Cpanel::Rand::Path::get_tmp_path($path);

    try {
        Cpanel::Autodie::symlink( $symlink_target, $tmpfile );
        Cpanel::Autodie::rename( $tmpfile, $path );
    }
    catch {
        Cpanel::Autodie::unlink_if_exists($tmpfile);
        local $@ = $_;
        die;
    };

    return 1;
}

#----------------------------------------------------------------------

sub _prefix {
    my ($self) = @_;

    my $class = ref($self) || $self;

    return join( '__', $class, 'PID', q<> );
}

sub DESTROY {
    my ($self) = @_;

    if ( $$ == $self->{'_pid'} ) {
        if ( $> != $self->{'_euid'} ) {
            die "XXX attempt to unlink($self->{'_path'}) as EUID $> rather than $self->{'_euid'}!";
        }

        Cpanel::Autodie::unlink_if_exists( $self->{'_path'} );
    }

    return;
}

1;
