
# cpanel - Cpanel/Install/Utils/Logger.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Install::Utils::Logger;

use strict;
use warnings;

use Cpanel::Output::Multi                        ();
use Cpanel::Output::Formatted::TerminalTimeStamp ();
use Cpanel::Output::Formatted::TimestampedPlain  ();
use Cpanel::Time::Local                          ();

my %call_map = (
    'DEBUG' => 'info',
    'ERROR' => 'error',
    'WARN'  => 'warn',
    'INFO'  => 'info',
    'FATAL' => 'error'
);
my $output_obj;

=encoding utf-8

=head1 NAME

Cpanel::Install::Utils::Logger - A logging utility for fresh cPanel installs.

=head1 SYNOPSIS

    use Cpanel::Install::Utils::Logger;

    Cpanel::Install::Utils::Logger::INFO("some info");
    Cpanel::Install::Utils::Logger::ERROR("some error");
    Cpanel::Install::Utils::Logger::WARN("some warning");
    Cpanel::Install::Utils::Logger::DEBUG("some debug info");
    Cpanel::Install::Utils::Logger::FATAL("fatal error.. and EXIT!");

=head2 DEBUG($msg)

Log a debug message

=head2 ERROR($msg)

Log an error message

=head2 WARN($msg)

Log an warning message

=head2 INFO($msg)

Log an informational message

=head2 FATAL($msg)

Log an fatal message and exit with code 1

=cut

sub DEBUG($) { return _MSG( 'DEBUG', "  " . shift ) }
sub ERROR($) { return _MSG( 'ERROR', shift ) }
sub WARN($)  { return _MSG( 'WARN',  shift ) }
sub INFO($)  { return _MSG( 'INFO',  shift ) }
sub FATAL($) { _MSG( 'FATAL', shift ); exit 1; }    ## no critic qw(Cpanel::NoExitsFromSubroutines) # See commit that added this line, refactoring out of scope

=head2 init($log_file)

Start logging to $log_file.

=cut

sub init {
    my ($log_file) = @_;

    open( my $log_fh, '>>', $log_file ) or die "Failed to open “$log_file”: $!";
    $output_obj = Cpanel::Output::Multi->new(
        output_objs => [
            Cpanel::Output::Formatted::TerminalTimeStamp->new( timestamp_method => \&Cpanel::Time::Local::localtime2timestamp ),
            Cpanel::Output::Formatted::TimestampedPlain->new( 'filehandle' => $log_fh, timestamp_method => \&Cpanel::Time::Local::localtime2timestamp )
        ]
    );

    return;
}

=head2 get_output_obj()

Return the Cpanel::Output object that was created
when init() was first called.

=cut

sub get_output_obj {
    if ( !$output_obj ) {
        require Carp;
        die Carp::longmess("init() must be called before get_output_obj()");
    }
    return $output_obj;
}

sub _MSG {
    my ( $level, $msg ) = @_;
    if ( !$output_obj ) {
        require Carp;
        die Carp::longmess("init() must be called before _MSG()");
    }
    $msg //= '';
    chomp $msg;
    my $stamp_msg = sprintf( "[%d] (%5s): %s\n", $$, $level, $msg );
    my $call      = $call_map{$level};
    return $output_obj->$call($stamp_msg);
}

1;

__END__
