package Cpanel::Pkgacct::Components::MysqlRemoteNotes;

# cpanel - Cpanel/Pkgacct/Components/MysqlRemoteNotes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

=head1 NAME

Cpanel::Pkgacct::Components::MysqlRemoteNotes - A pkgacct component module to move a user's MySQL Remote notes

=head1 SYNOPSIS

    use Cpanel::Config::LoadCpConf;
    use Cpanel::Pkgacct;
    use Cpanel::Pkgacct::Components::MysqlRemoteNotes;
    use Cpanel::Output::Formatted::Terminal;

    my $user = 'root';
    my $work_dir = '/root/';
    my $pkgacct = Cpanel::Pkgacct->new(
        'is_incremental'    => 1,
        'is_userbackup'     => 1,
        'is_backup'         => 1,
        'user'              => $user,
        'new_mysql_version' => 'default',
        'uid'               => ( ( Cpanel::PwCache::getpwnam( $user ) )[2] || 10 ),
        'suspended'         => 1,
        'work_dir'          => $work_dir,
        'dns_list'          => 1,
        'domains'           => [],
        'now'               => time(),
        'cpconf'            => scalar Cpanel::Config::LoadCpConf::loadcpconf(),
        'OPTS'              => { 'db_backup_type' => 'all' },
        'output_obj'        => Cpanel::Output::Formatted::Terminal->new(),
    );

    $pkgacct->build_pkgtree($work_dir);
    $pkgacct->perform_component("MysqlRemoteNotes");

=head1 DESCRIPTION

This module implements a C<Cpanel::Pkgacct::Component> module. It is
responsible for packaging the MySQL Remote notes for a given user.

=cut

use Cpanel::Mysql::Remote::Notes ();
use Cpanel::FileUtils::Copy      ();
use Cpanel::LoadModule           ();
use Cpanel::Exception            ();

use Try::Tiny;

=head2 perform()

The function that actually does the work of moving the notes file for
a user. It will only backup the notes file if it exists and is out
of date.

B<Returns>: C<1>

=cut

sub perform {
    my $self = shift;

    my $user       = $self->get_user();
    my $work_dir   = $self->get_work_dir();
    my $output_obj = $self->get_output_obj();

    # CPANEL-34777: Only root has access to the notes directory and file.
    if ($>) {
        try {
            Cpanel::LoadModule::load_perl_module('Cpanel::AdminBin::Call');

            my $notes = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'GET_HOST_NOTES' );

            if ( ref $notes eq 'HASH' ) {

                # Don't bother if empty:
                if ( scalar keys %$notes > 0 ) {
                    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::JSON');
                    my $txn = Cpanel::Transaction::File::JSON->new( path => "$work_dir/mysql_host_notes.json" );
                    $txn->set_data($notes);
                    $txn->save_and_close_or_die();
                }
            }
            else {
                die Cpanel::Exception->create_raw('Unexpected return data type from adminbin Cpanel/mysql/GET_HOST_NOTES');
            }
        }
        catch {
            $output_obj->warn( Cpanel::Exception::get_string($_) );
        };
    }
    else {
        my $notes_obj  = Cpanel::Mysql::Remote::Notes->new( username => $user );
        my $notes_file = $notes_obj->{filename};

        if (
            -f $notes_file
            and $self->file_needs_backup(
                $notes_file,
                "$work_dir/mysql_host_notes.json", "mysql_host_notes.json",
            )
        ) {
            Cpanel::FileUtils::Copy::safecopy(
                $notes_file,
                "$work_dir/mysql_host_notes.json",
            );
        }
    }

    return 1;
}

1;
