package Cpanel::Syscall;

# cpanel - Cpanel/Syscall.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf8

=head1 NAME

Cpanel::Syscall - Conveniences for running system calls

=head1 SYNOPSIS

    #This will give the correct number for the platform,
    #i.e., depending on whether this is a 32- or 64-bit kernel.
    #Throws on an unknown system call.
    my $num = Cpanel::Syscall::name_to_number('close');

    #Do a system call. Throws on error.
    my $result = Cpanel::Syscall::syscall( $name, @args );

=head1 DESCRIPTION

There’s not much to say that the SYNOPSIS doesn’t cover, except:

=over 4

=item * To run a system call via this module, the module has to know how
to translate the call’s name into a number. That number will be different
for a 32-bit kernel than it is for a 64-bit kernel, so we need to know both.
To “teach” this module how to use a new system call, add the name and its
32- and 64-bit numbers to the module’s internal list.

=item * C<syscall()> will throw a C<Cpanel::Exception::SystemCall> instance
if the C<Cpanel::Exception> module is loaded; otherwise, C<syscall()> will
throw a simple string.

=back

=cut

use strict;
## no critic(RequireUseWarnings)

#This is ugly, but we do it this way to minimize memory usage.
# _set_system_call_numbers: do not use a function to cleanup after BEGIN
#THIS IS THE MODULE’S INTERNAL LIST OF SYSTEM CALLS.
#It is kept as an array to minimize memory usage.
#
#These numbers obtained from /usr/include/asm/unistd_64.h
#Note: We use the unsigned version, if available, for larger number support
#
#NOTE: When adding a call here, please also add it to the list
#in this module’s test suite.
#
#name   64-bit
#
my %NAME_TO_NUMBER = qw(
  close             3
  fcntl            72
  lchown           94
  getrlimit        97
  getsid          124
  gettimeofday     96
  sendfile         40
  setrlimit       160
  splice          275
  write             1
  setsid          112
  getsid          124
  inotify_init1     294
  inotify_add_watch 254
  inotify_rm_watch  255
  setresuid       117
  setresgid       119
  setgroups       116
  umount2         166
);

sub name_to_number {
    my ($name) = @_;

    return $NAME_TO_NUMBER{$name} || _die_unknown_syscall($name);
}

sub _die_unknown_syscall {
    my ($name) = @_;

    #There’s no point in throwing an object here since
    #an error here means the programmer typed the wrong name or something.
    die "Unknown system call: “$name”";
}

#Like Perl’s built-in, except that its first argument is the
#NAME of a system call (e.g., “setrlimit”), not its numeric value.
#
#Also unlike Perl’s built-in, this throws an exception
#on failure. If Cpanel::Exception is loaded, it will throw an appropriate
#exception object; otherwise, it throws a simple string.
#
# $_[0] = name of syscall
# $_[1..] = args
sub syscall {    ##no critic qw(RequireArgUnpacking)
    local $!;

    _die_unknown_syscall( $_[0] ) unless defined $_[0] && $NAME_TO_NUMBER{ $_[0] };

    # don’t add any extra call stack layer here (generates a segfault on some arch)
    my $ret = CORE::syscall( $NAME_TO_NUMBER{ $_[0] }, scalar @_ > 1 ? @_[ 1 .. $#_ ] : () );
    if ( ( $ret == -1 ) && $! ) {
        if ( $INC{'Cpanel/Exception.pm'} ) {
            die Cpanel::Exception::create( 'SystemCall', [ name => $_[0], error => $!, arguments => [ @_[ 1 .. $#_ ] ] ] );
        }
        else {
            die "Failed system call “$_[0]”: $!";
        }
    }

    return $ret;
}

1;
