package Cpanel::Pkgacct::Components::APITokens;

# cpanel - Cpanel/Pkgacct/Components/APITokens.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Pkgacct::Component';

use Cpanel::AdminBin::Call                       ();
use Cpanel::Autodie                              ();
use Cpanel::FileUtils::Write                     ();
use Cpanel::JSON                                 ();
use Cpanel::Security::Authn::APITokens::cpanel   ();    # PPI NO PARSE
use Cpanel::Security::Authn::APITokens::whostmgr ();    # PPI NO PARSE

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Components::APITokens - A pkgacct component module to move a user's api tokens

=head1 SYNOPSIS

    use Cpanel::Config::LoadCpConf;
    use Cpanel::Pkgacct;
    use Cpanel::Pkgacct::Components::APITokens;
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
    $pkgacct->perform_component("APITokens");

=head1 DESCRIPTION

This module implements a C<Cpanel::Pkgacct::Component> module. It is responsible for packaging the
access token data for a given user.

=cut

=head2 perform()

The function that actually does the work of backing up a user’s token
data.
It will only back up data that’s newer than the existing backup.

B<Returns>: C<1>

=cut

sub perform {
    my ($self) = @_;

    my $username = $self->get_user();

    my $work_dir = $self->get_work_dir();
    Cpanel::Autodie::mkdir_if_not_exists("$work_dir/api_tokens");

    for my $svc_name (qw( cpanel whostmgr )) {

        my $tokens_hr;

        my $target_path = "$work_dir/api_tokens/$svc_name";

        if ( $svc_name eq 'whostmgr' && $> ) {
            $tokens_hr = Cpanel::AdminBin::Call::call( 'Cpanel', 'whmapitokens', 'READ' );
        }
        else {

            my $module = "Cpanel::Security::Authn::APITokens::$svc_name";

            my $mtime = $module->get_user_mtime($username);
            next if !$mtime;

            next if !$self->mtime_needs_backup(
                $mtime,
                $target_path,
                $svc_name,
            );

            my $token_obj = $module->new( { user => $username } );

            $tokens_hr = $token_obj->read_tokens();
            $_         = $_->export() for values %$tokens_hr;
        }

        if (%$tokens_hr) {

            my $json = Cpanel::JSON::Dump($tokens_hr);

            Cpanel::FileUtils::Write::write( $target_path, $json );
        }

    }

    return 1;
}

1;
