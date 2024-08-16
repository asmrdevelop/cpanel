package Cpanel::Update::Start;

# cpanel - Cpanel/Update/Start.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Update::Start

=head1 SYNOPSIS

    my ($upid, $logpath) = Cpanel::Update::Start::start();

=head1 DESCRIPTION

This module implements logic to start a cPanel & WHM update from Perl.

=cut

#----------------------------------------------------------------------

use Cpanel::ConfigFiles     ();
use Cpanel::Context         ();
use Cpanel::SafeRun::Object ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 ($pid, $logpath, $is_new) = start( %ARGS )

Attempts to start an update.

%ARGS are:

=over

=item C<mode>: Optional. Either C<sync> or C<force>.
See F</scripts/upcp> for what those do.

=back

Returns a list:

=over

=item * The backgrounded update process’s ID.

=item * The filesystem path to the update process’s log.

=item * A boolean that indicates whether the update process is
newly-launched. This will always be truthy if C<mode> is C<force>.

=back

=cut

my %MODE_ARGS = (
    sync  => ['--sync'],
    force => ['--force'],
);

sub start (%args) {
    Cpanel::Context::must_be_list();

    my @mode_args;

    my $mode = $args{'mode'};

    if ( defined $mode ) {
        my $args_ar = $MODE_ARGS{$mode} or do {
            my @modes = sort keys %MODE_ARGS;
            die "Invalid “mode” ($mode)! Omit, or give one of: @modes\n";
        };

        @mode_args = @$args_ar;
    }

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/upcp",
        args    => [ '--bg', @mode_args ],
    );

    return _parse_run_output( $run->stdout() );
}

sub _parse_run_output ($stdout) {

    # See scripts/upcp for the source phrases that these intend to match.

    my ($path) = ( $stdout =~ m<“(.+?\.log)”> ) or do {
        die "No path found in upcp output: $stdout";
    };

    my ($pid) = ( $stdout =~ m<PID ([0-9]+)> ) or do {
        die "No PID found in upcp output: $stdout";
    };

    my ($already) = $stdout =~ m<\balready\b>;

    return ( $pid, $path, !$already );
}

1;
