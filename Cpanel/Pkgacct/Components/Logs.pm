package Cpanel::Pkgacct::Components::Logs;

# cpanel - Cpanel/Pkgacct/Components/Logs.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::Logs

=head1 SYNOPSIS

    $pkgacct->perform_component('Logs');

=head1 DESCRIPTION

This module implements backups for user log files (e.g., HTTP, mail, FTP).

=cut

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::ConfigFiles::Apache              ();
use Cpanel::Pkgacct                          ();
use Cpanel::Pkgacct::Components::Logs::Utils ();
use Cpanel::SimpleSync::CORE                 ();

use constant {
    _ENOENT         => 2,
    _FORK_THRESHOLD => 64 * 1024 * 1024,
};

#overridden in tests
sub _get_logs_directory {
    return Cpanel::ConfigFiles::Apache->new()->dir_domlogs();
}

=head1 FUNCTIONS

=head2 I<OBJ>->perform()

Do the log file backup.

=cut

sub perform {
    my ($self) = @_;

    my $username   = $self->get_user();
    my $output_obj = $self->get_output_obj();
    my $work_dir   = $self->get_work_dir();

    my $possible_log_files_hr = Cpanel::Pkgacct::Components::Logs::Utils::get_user_log_files_lookup($username);

    my $total_log_size = 0;
    my @logfiles;
    my $dir_domlogs = _get_logs_directory();

    my $we_are_root = !$>;

    my @log_files_to_check_for;

    #$possible_log_files_hr is likely much bigger than the number of
    #nodes in $dir_domlogs, so we can save a lot of stat()s by
    #prefetching the list of nodes. (This only works for root.)
    if ( $we_are_root && opendir( my $domlog_dh, $dir_domlogs ) ) {
        local $!;

        @log_files_to_check_for = grep { exists $possible_log_files_hr->{$_} } readdir($domlog_dh);

        warn "readdir($dir_domlogs): $!" if $!;
    }
    else {
        warn "opendir($dir_domlogs): $!" if $we_are_root;

        @log_files_to_check_for = keys %$possible_log_files_hr;
    }

    foreach my $log (@log_files_to_check_for) {
        my $size = -s "$dir_domlogs/$log";

        if ( !defined $size ) {
            warn "stat($dir_domlogs/$log): $!" if $! != _ENOENT;
            next;
        }

        $total_log_size += $size;
        push @logfiles, $log;
    }

    if (@logfiles) {    #only fork if we have log files to copy
        my $log_file_copy_ref = sub {
            foreach my $logfile (@logfiles) {
                $output_obj->out( "...$logfile...", @Cpanel::Pkgacct::PARTIAL_MESSAGE );
                $self->syncfile_or_warn(
                    "$dir_domlogs/$logfile",
                    "$work_dir/logs",
                    $Cpanel::SimpleSync::CORE::FOLLOW_SYMLINKS,
                    $Cpanel::SimpleSync::CORE::NO_CHOWN,
                    $Cpanel::SimpleSync::CORE::RESUMABLE,
                );
            }
        };

        $output_obj->out( "...log file sizes [$total_log_size byte(s)]...", @Cpanel::Pkgacct::PARTIAL_MESSAGE );

        if ( $total_log_size < _FORK_THRESHOLD() ) {
            $log_file_copy_ref->();
        }
        else {
            $self->run_dot_event(
                sub {
                    $0 = "pkgacct - $username - log copy child";    ## no critic qw( RequireLocalizedPunctuationVars )
                    $log_file_copy_ref->();
                },
            );
        }
    }

    return;
}

1;
