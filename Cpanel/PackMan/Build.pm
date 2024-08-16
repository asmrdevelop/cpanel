package Cpanel::PackMan::Build;

# cpanel - Cpanel/PackMan/Build.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Moo;

use IO::Handle               ();
use Cpanel::Rand             ();
use Cpanel::Time             ();
use Cpanel::Daemonizer::Tiny ();
use Cpanel::Logger           ();

our $VERSION = "0.02";

with 'Role::Multiton';

has log_dir => (
    is       => 'rw',
    isa      => sub { die "must be a directory" if !-d $_[0]; die "must be absolute path" if substr( $_[0], 0, 1 ) ne "/" },    # absolute because Cpanel::Daemonizer::Tiny changes directory
    required => 1,
);

has _pid_obj => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        use Cpanel::Unix::PID::Tiny ();    # no need for lazy loading so that it gets compiled in via perlcc, have the use() here to keep it all together since nothing else will be using it directly
        return Cpanel::Unix::PID::Tiny->new;
    },
);

sub is_running {
    my ($self) = @_;
    my $target = readlink( $self->log_dir . "/current_build" );
    return unless $target;
    my $pidfile = "$target.pid";
    return $target if !-e $pidfile || $self->_pid_obj->is_pidfile_running($pidfile);    # we have a link but no pid file means we just raced a build was commencing

    return;
}

sub start {
    my ( $self, $code, @code_args ) = @_;
    return if $self->is_running;                                                        # skip the setup if one is running

    my $subdir = $self->log_dir . '/' . Cpanel::Time::time2dnstime();                   # $YYYYMMDD;
    mkdir( $subdir, 0700 );

    my $random_file = Cpanel::Rand::get_tmp_file_by_name( "$subdir/", $$ );
    return if $self->is_running;                                                        # make sure no-one started one while we were setting up (over kill to do two? if so which one stays?)

    unlink $self->log_dir . "/current_build";                                           # we have a stale file and it'd prevent symlink() from doing its thing
    symlink $random_file, $self->log_dir . "/current_build";

    if ( readlink( $self->log_dir . "/current_build" ) ne $random_file ) {
        return;                                                                         # looks like we hit a race and someone else beat us
    }

    my $pointer_file = $self->log_dir . "/current_build";

    my $pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            my $_logger = Cpanel::Logger->new();
            my $random_fh;
            open( $random_fh, '>>', $random_file ) or $_logger->die("Failed to open $random_file: $!");
            open( STDIN, '<', '/dev/null' ) || $_logger->die("PackMan::start: Failed to redirect STDIN to /dev/null : $!");
            open( STDOUT, '>&=' . fileno($random_fh) ) || $_logger->die("PackMan::start: Could not redirect STDERR to $random_file: $!");    ## no critic qw(ProhibitTwoArgOpen)
            open( STDERR, '>&=' . fileno($random_fh) ) || $_logger->die("PackMan::start: Could not redirect STDERR to $random_file: $!");    ## no critic qw(ProhibitTwoArgOpen)
            *STDERR->autoflush();
            *STDOUT->autoflush();

            print "-- $$ --\n";
            eval { $code->(@code_args) };
            my $err = $@;
            chomp($err);
            print "\n-- error($$) --\n$err\n-- /error($$) --\n" if $err;
            print "\n-- /$$ --\n";

            unlink($pointer_file);
            $_logger->die("PID $$ could not cleanup pointer file\n") if -l $pointer_file;
        }
    );

    # Do pid file outside of spork so that we'll have the pid to look for if the process bails before it could write it
    open( my $pfh, ">", "$random_file.pid" ) or die "Could not write “$random_file.pid”: $!\n";
    print {$pfh} $pid;
    close $pfh;

    return $pid;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::PackMan::Build - cPanel package management build object

=head1 VERSION

This document describes Cpanel::PackMan::Build version 0.01

=head1 SYNOPSIS

   # via Cpanel::PackMan’s build façade
   my $pkm = Cpanel::PackMan->instance;

   if ($pkm->build->is_running) {
       say "Well you better go catch it!";
   }


   my $pid = $pkm->build->start(sub {
       $pkm->sys->install(…);
       …
   }) || die "Could not start build!!!";

   # directly
   my $bld = Cpanel::PackMan::Build->instance(log_dir => $dir);

   if ($bld->is_running) {
       say "Well you better go catch it!";
   }

=head1 DESCRIPTION

Package management build related methods.

=head1 INTERFACE

=head2 Constructors

=head3 new()

This will create and return a new object everytime.

Its options are described under </ATTRIBUTES>.

=head3 instance()/multiton()

Like new() but returns the same object on subsequent calls using the same arguments.

=head2 ATTRIBUTES

=head3 log_dir

Required. The directory where build files go.

=head2 Methods

=head3 is_running

Takes no arguments.

Returns a boolean of whether or not a build is currently running.

The true value is also the output file.

=head3 start

Takes a coderef that does the desired build and, optionally, any arguments to that coderef.

Spork()s it off in a way that it can be tailed via $self->log_dir . '/current_build'

Return the PID of the spork’d process.
