package Cpanel::API::Restore;

# cpanel - Cpanel/API/Restore.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AdminBin::Call ();
use Cpanel::Math           ();

my $allow_demo = { allow_demo => 1 };

our %API = (
    _needs_role       => 'FileStorage',
    _needs_feature    => "filerestoration",
    directory_listing => $allow_demo,
    query_file_info   => $allow_demo,
    restore_file      => $allow_demo,
    get_users         => $allow_demo,
);

=encoding utf-8

=head1 NAME

Cpanel::API::Restore - Provides a cPanel API to access backup's for file restore.

=head1 SYNOPSIS

    use Cpanel::API::Restore;

    CLI:

    uapi -u <cpanel_user> Restore directory_listing path=/
    uapi -u <cpanel_user> Restore query_file_info path=/public_html/.htaccess

=head1 DESCRIPTION

This module contains functions for browsing backups on behalf of a user.   This escalates priveleges
via admin bin calls to bin/admin/Cpanel/restore.

=cut

=head2 directory_listing

Returns a list of files and sub directories in all of this user's backups.  The
resulting list of files and dirs are union of all files and dirs in all of the
backups.

=over 2

=item Input

=back

=over 3

=item C<Cpanel::Args> path (required) - The path in the backup to get a listing

path - must begin and end with a slash.  path of / means the
files and dirs in the users homedir.

=back

=over 2

=item Output

=back

=over 3

=item C<Cpanel::Result>

    • [root@julian64:/usr/local/cpanel] (HB-2718)# bin/uapi -u abc1 Restore directory_listing path=/public_html/
    ---
    apiversion: 3
    func: directory_listing
    module: Restore
    result:
    data:
        -
            exists: 1
            name: .htaccess
            type: file
        -
            exists: 1
            name: index.php
            type: file
    errors: ~
    messages: ~
    metadata:
        transformed: 1
    status: 1

=back

=cut

sub directory_listing {
    my ( $args, $result ) = @_;

    my $paginate = "NOPAGE";
    if ( $args->{'_pagination'} ) {
        $paginate = {
            '_start' => $args->{'_pagination'}->{'_start'},
            '_size'  => $args->{'_pagination'}->{'_size'},
            '_page'  => $args->{'_pagination'}->{'_page'},
        };
    }

    my ($path) = $args->get_length_required('path');
    my $output = Cpanel::AdminBin::Call::call( 'Cpanel', 'restore', 'DIRECTORYLISTING', { 'path' => $path, 'paginate' => $paginate } );

    my $records       = $output->{'records'};
    my $total_records = $output->{'total_records'};

    $result->data($records);

    if ( $args->{'_pagination'} ) {
        my $pagination = $args->{'_pagination'};
        $result->total_results($total_records);
        my $page_results = {
            'total_results'    => $total_records,
            'total_pages'      => Cpanel::Math::ceil( $result->total_results() / $pagination->size() ),
            'start_result'     => 1 + $pagination->start(),
            'results_per_page' => $pagination->size(),
            'current_page'     => Cpanel::Math::ceil( ( 1 + $pagination->start() ) / $pagination->size() ),
        };

        $result->metadata( 'paginate', $page_results );
        $result->mark_as_done($pagination);
    }

    return 1;
}

=head2 query_file_info

Returns a list of all backups the specified file is in and stats about that file
in each of those backups.

=over 2

=item Input

=back

=over 3

=item C<Cpanel::Args> path (required) - The path to the file in backups.

path - must begin slash.

=back

=over 2

=item Output

=back

=over 3

=item C<Cpanel::Result>

    • [root@julian64:/usr/local/cpanel] (HB-2718)# bin/uapi -u abc1 Restore query_file_info path=/public_html/index.php
    ---
    apiversion: 3
    func: query_file_info
    module: Restore
    result:
        data:
        -
            backupDate: 2017-07-01
            backupID: monthly/2017-07-01
            fileSize: 199
            path: /public_html/index.php
            modifiedDate: 2017-06-02 12:18
        -
            backupDate: 2017-07-02
            backupID: weekly/2017-07-02
            fileSize: 199
            path: /public_html/index.php
            modifiedDate: 2017-06-02 12:18
        -
            backupDate: 2017-07-05
            backupID: 2017-07-03
            fileSize: 199
            path: /public_html/index.php
            modifiedDate: 2017-06-02 12:18
        -

        ...

=back

=cut

sub query_file_info {
    my ( $args, $result ) = @_;

    # Preserve former argument name if still used
    if ( defined $args->{'_args'}{'fullpath'} ) {
        $args->{'_args'}{'path'} = $args->{'_args'}{'fullpath'};
    }
    my ($fullpath)                     = $args->get_length_required('path');
    my ($return_exists_flag_to_caller) = $args->get('exists');
    $return_exists_flag_to_caller //= 0;

    my $output = Cpanel::AdminBin::Call::call( 'Cpanel', 'restore', 'QUERYFILEINFO', { 'path' => $fullpath, 'exists' => $return_exists_flag_to_caller } );

    $result->data($output);

    return 1;
}

=head2 restore_file

Restores a file from a backup.

=over 2

=item Input

=back

=over 3

=item C<Cpanel::Args> path (required) - The path to the file in backups.

path - must begin slash.

=back

=over 3

=item C<Cpanel::Args> backupID (required) - The ID of the backup, see output from query_info_file.

backupID - either Date, monthly/Date or weekly/Date

=back

=over 3

=item C<Cpanel::Args> overwrite (required) - 1 or 0, if the file already exists in the users directories a 1 will allow it to be overwritten, otherwise the function will error out.

exists - 1 or 0

=back

=over 2

=item Output

=back

=over 3

=item None

=back

=cut

sub restore_file {
    my ( $args, $result ) = @_;

    # Preserve former argument name if still used
    if ( defined $args->{'_args'}{'fullpath'} ) {
        $args->{'_args'}{'path'} = $args->{'_args'}{'fullpath'};
    }

    my ($backupID)  = $args->get_length_required('backupID');
    my ($fullpath)  = $args->get_length_required('path');
    my ($overwrite) = $args->get_length_required('overwrite');

    my $output = Cpanel::AdminBin::Call::call(
        'Cpanel',
        'restore',
        'RESTOREFILE',
        {
            'backupID'  => $backupID,
            'path'      => $fullpath,
            'overwrite' => $overwrite
        }
    );

    $result->data($output);

    return 1;
}

=head2 get_users

Returns a list of users which you own (e.g. resell) with existing backup metadata.

In the event this is a 'normal' cPanel user, its own name will be returned.

=over 2

=item Input

=back

=over 3

=item C<None>

=back

=over 2

=item Output

=back

=over 3

=item ARRAY of account names with existing backup metadata.

=back

=cut

sub get_users {
    my ( $args, $result ) = @_;

    my $output = Cpanel::AdminBin::Call::call( 'Cpanel', 'restore', 'GETUSERS' );

    $result->data($output);

    return 1;
}

1;
