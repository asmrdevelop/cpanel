package Cpanel::Pkgacct::Components::Cron;

# cpanel - Cpanel/Pkgacct/Components/Cron.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::Cron

=head1 SYNOPSIS

    my $obj = Cpanel::Pkgacct->new( ... );
    $obj->perform_component('Cron');

=head1 DESCRIPTION

This module exists to be called from L<Cpanel::Pkgacct>. It should not be
invoked directly except from that module.

It backs up the user’s web calls information.

=head1 METHODS

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Pkgacct::Component';

# Mocked in tests
our @_POSSIBLE_CRON_DIRS;

BEGIN {
    @_POSSIBLE_CRON_DIRS = (
        '/var/spool/cron/crontabs',
        '/var/cron/tabs',
        '/var/spool/cron',
        '/var/spool/fcron',
        '/var/spool/cron.suspended',
    );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->perform()

This is just here to satisfy cplint. Don’t call this directly.

=cut

sub perform ($self) {
    my $output_obj = $self->get_output_obj();

    my $copied_cron = 0;

    my $user     = $self->get_user();
    my $work_dir = $self->get_work_dir();

    my $work_dir_cron_path = "$work_dir/cron/$user";

    foreach my $path ( map { "$_/$user" } @_POSSIBLE_CRON_DIRS ) {
        if ( -r $path ) {
            $output_obj->out( "Readable crontab file ($path) found; copying …", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );

            $self->syncfile_or_warn( $path, $work_dir_cron_path );
            $copied_cron = 1;

            last;
        }
    }

    if ( !$copied_cron ) {
        if ( $> == 0 ) {
            $output_obj->out( "No readable crontab file found.", @Cpanel::Pkgacct::NOT_PARTIAL_TIMESTAMP );
        }
        else {
            $output_obj->out('Saving output of “crontab” …');
            $self->simple_exec_into_file( $work_dir_cron_path, [ 'crontab', '-l' ] );
        }
    }

    return 1;
}

1;
