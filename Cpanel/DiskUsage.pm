package Cpanel::DiskUsage;

# cpanel - Cpanel/DiskUsage.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                       ();
use Cpanel::Email::Accounts      ();
use Cpanel::FileUtils::Dir       ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::Logger               ();
use Cpanel::DiskCounter          ();
use Cpanel::Email::DiskUsage     ();
use Cpanel::LoadFile             ();
use Cpanel::Locale               ();
use Cpanel::Quota                ();
use Cpanel::MysqlFE::DB          ();
use Cpanel::FileUtils::Write     ();

use Try::Tiny;

my $APIref;
my $logger;

our $MAIL_DIR_VSIZE = 4096;

our $VERSION = '1.6';

sub DiskUsage_init { }

sub api2_buildcache {
    if ( -e "$Cpanel::homedir/.cpanel/ducache" ) {
        my $umtime = ( stat("$Cpanel::homedir/.cpanel/ducache") )[9];
        my $now    = time();
        if ( ( $umtime + 485 ) > $now && $umtime <= $now ) {    #timewarp safe
            return [ { 'status' => 1, 'statusmsg' => 'cache already exists' } ];
        }
    }

    # CPANEL-32648: Force-update the email accounts db cache before trying to update the disk cache.
    Cpanel::Email::Accounts::manage_email_accounts_db( 'event' => 'sync', 'ttl' => 1 );

    _fetch_disk_usage( 'nocache' => 1 );    # this will build the cache and write the mail usage correctly

    return [ { 'status' => 1, 'statusmsg' => 'cache built' } ];
}

sub api2_clearcache {
    unlink $Cpanel::homedir . '/.cpanel/ducache';
    return [ { 'status' => 1, 'statusmsg' => 'cache cleared' } ];
}

sub cache_filemap {
    my ($rFileMap) = @_;
    _create_dot_cpanel_dir();

    my $ret;
    try {
        $ret = Cpanel::FileUtils::Write::overwrite( $Cpanel::homedir . '/.cpanel/ducache', Cpanel::AdminBin::Serializer::Dump($rFileMap), 0600 );

    }
    catch {
        # case CPANEL-17546:
        # If this fails we can still return the result
        # but we cannot cache it.  Usually this means
        # they are overquota
        local $@ = $_;
        warn;

    };
    return $ret;
}

sub _create_dot_cpanel_dir {
    if ( !-e "$Cpanel::homedir/.cpanel" ) {
        if ( !mkdir( "$Cpanel::homedir/.cpanel", 0700 ) ) {
            $logger ||= Cpanel::Logger->new();
            $logger->warn( 'Could not create dir "' . "$Cpanel::homedir/.cpanel" . '"' );
        }
    }
    return;
}

sub _load_cached_filemap {
    my $rFileMap;
    _create_dot_cpanel_dir();
    if ( -e "$Cpanel::homedir/.cpanel/ducache" ) {
        my $umtime = ( stat("$Cpanel::homedir/.cpanel/ducache") )[9];
        my $now    = time();
        if ( ( $umtime + 500 ) > $now && $umtime <= $now ) {    #timewarp safe
            eval { $rFileMap = Cpanel::AdminBin::Serializer::LoadFile("$Cpanel::homedir/.cpanel/ducache"); };
        }
    }
    return $rFileMap;
}

my %_Key_Conversions = (
    '/'                    => 'contents',
    '/type'                => 'type',
    '/size'                => 'usage',
    '/child_node_sizes'    => 'contained_usage',
    'traversible'          => 'traversible',
    'user_contained_usage' => 'user_contained_usage',
    'owner'                => 'owner',
);

sub api2_fetchdiskusage {
    return _api2_fetchdiskusage(@_)->{'api2_disk_usage'};
}

sub _api2_fetchdiskusage {
    my %OPTS = @_;

    my $rFileMap = _fetch_disk_usage(%OPTS);
    my ( $this_file_data, $contents );
    my $root_contents = delete $rFileMap->{'/'};

    my $mailarchives_usage = exists $root_contents->{'mail'} && exists $root_contents->{'mail'}{'/'}{'archive'} ? ( $root_contents->{'mail'}{'/'}{'archive'}{'/size'} + $root_contents->{'mail'}{'/'}{'archive'}{'/child_node_sizes'} ) : 0;
    my $mailaccounts_usage = exists $root_contents->{'mail'}                                                    ? ( $root_contents->{'mail'}{'/size'} + $root_contents->{'mail'}{'/child_node_sizes'} ) - $mailarchives_usage           : 0;
    my $disk_usage         = {

        # generate usage,type,contained_usage for the root key
        ( map { exists $_Key_Conversions{$_} ? ( $_Key_Conversions{$_} => $rFileMap->{$_} ) : () } keys %{$rFileMap} ),
        'name'     => exists $OPTS{'path'} ? $OPTS{'path'} : $Cpanel::homedir,
        'contents' => [
            map {
                $this_file_data = $root_contents->{$_};
                $contents       = delete $this_file_data->{'/'};
                {
                    'name'     => $_,
                    'contents' => defined($contents) ? scalar keys %$contents : undef,
                    ( map { exists $_Key_Conversions{$_} ? ( $_Key_Conversions{$_} => $this_file_data->{$_} ) : () } keys %{$this_file_data} ),
                }
              }
              sort keys %$root_contents
        ],
    };

    return {
        'api2_disk_usage'    => $disk_usage,
        'mailarchives_usage' => $mailarchives_usage,
        'mailaccounts_usage' => $mailaccounts_usage,
    };
}

sub api2_fetch_raw_disk_usage {
    my %OPTS = @_;

    my $rFileMap = _fetch_disk_usage(%OPTS);

    return [ { 'diskusage' => $rFileMap } ];
}

sub _fetch_disk_usage {
    my %OPTS = @_;
    my $rFileMap;
    if ( !$OPTS{'nocache'} ) {
        $rFileMap = _load_cached_filemap();
    }
    if ( !$rFileMap ) {
        $rFileMap = Cpanel::DiskCounter::disk_counter( $Cpanel::homedir, $Cpanel::DiskCounter::NO_FILES, undef, $Cpanel::DiskCounter::SKIP_MAIL );

        _augment_contents_with_mail_usage($rFileMap);
        _augment_contents_with_mail_archive_usage($rFileMap);

        cache_filemap($rFileMap);
    }

    if ( $OPTS{'path'} ) {
        my $showtree = $OPTS{'path'};
        $showtree =~ s/\.\.//g;
        $showtree =~ s/^\/\*//g;
        my @path = split( /\/+/, $showtree );
        while ( my $dir = shift @path ) {
            $rFileMap = $rFileMap->{'/'}->{$dir};
        }
    }

    return $rFileMap;
}

sub api2_fetchdiskusagewithextras {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $api2_fetchdiskusage = _api2_fetchdiskusage(@_);

    my $counted_usage = $api2_fetchdiskusage->{'api2_disk_usage'};
    my $mailarchives  = $api2_fetchdiskusage->{'mailarchives_usage'};
    my $mailaccounts  = $api2_fetchdiskusage->{'mailaccounts_usage'};

    #return bytes rather than MiB; do not include DB disk usage
    my ( $used, $limit ) = Cpanel::Quota::displayquota( 1, 0 );

    require Cpanel::UserDatastore;

    my $datastore = {};
    foreach my $source (qw{mysql-disk-usage postgres-disk-usage mailman-disk-usage}) {
        my $f = Cpanel::UserDatastore::get_path($Cpanel::user) . "/$source";
        next if !-e $f;
        $datastore->{$source} = int( Cpanel::LoadFile::loadfile($f) || 0 );
    }

    if ( !defined($used) || $used eq 'NA' || $used eq $Cpanel::Quota::QUOTA_NOT_ENABLED_STRING ) {
        $used  = undef;
        $limit = undef;
    }
    else {
        $used  = int $used;
        $limit = defined $limit ? int $limit : undef;
    }

    ## the !! is to force a 0 or 1
    my $skipmailman = exists $Cpanel::CONF{'skipmailman'} ? !!$Cpanel::CONF{'skipmailman'} : 0;

    return {
        'homedir'    => $counted_usage,
        'quotaused'  => $used,
        'quotalimit' => $limit,
        'mailman'    => $datastore->{'mailman-disk-usage'} || 0,

        'mailaccounts' => defined $mailaccounts                       ? int $mailaccounts                : undef,
        'mysql'        => defined( $datastore->{'mysql-disk-usage'} ) ? $datastore->{'mysql-disk-usage'} : _get_mysql_usage(),
        'pgsql'        => $datastore->{'postgres-disk-usage'} || 0,

        'mailarchives' => defined $mailarchives ? int $mailarchives : undef,
        'skipmailman'  => $skipmailman,
    };
}

sub _get_mysql_usage {
    my %DBS = Cpanel::MysqlFE::DB::listdbswithspace();
    my $usage;
    for ( values %DBS ) {
        $usage += $_;
    }
    return $usage;
}

sub _augment_contents_with_mail_usage {
    my ($root_node) = @_;

    my $mail_node = $root_node->{'/'}{'mail'} or return;

    my $maildir = "$Cpanel::homedir/mail";

    my $mainacct_disk_used_bytes = Cpanel::Email::DiskUsage::get_disk_used( '_mainaccount', $Cpanel::CPDATA{'DNS'} );

    # /
    $root_node->{'user_contained_usage'} += $mainacct_disk_used_bytes;
    $root_node->{'/child_node_sizes'}    += $mainacct_disk_used_bytes;

    # /mail
    $mail_node->{'user_contained_usage'} += $mainacct_disk_used_bytes;
    $mail_node->{'/child_node_sizes'}    += $mainacct_disk_used_bytes;

    my ( $domain_mail_dir_size, $domain_mail_node );

    my ( $mail_info, $_manage_err ) = Cpanel::Email::Accounts::manage_email_accounts_db( 'event' => 'fetch' );
    foreach my $domain ( keys %$mail_info ) {
        $domain_mail_dir_size = ( lstat("$maildir/$domain") )[7] or next;

        # /
        $root_node->{'user_contained_usage'} += $domain_mail_dir_size;
        $root_node->{'/child_node_sizes'}    += $domain_mail_dir_size;

        # /mail
        $mail_node->{'user_contained_usage'} += $domain_mail_dir_size;
        $mail_node->{'/child_node_sizes'}    += $domain_mail_dir_size;

        $mail_node->{'/'}{$domain} = _node_template($domain_mail_dir_size);

        $domain_mail_node = $mail_node->{'/'}{$domain};
        foreach my $user ( keys %{ $mail_info->{$domain}{'accounts'} } ) {
            my $diskused = $mail_info->{$domain}{'accounts'}{$user}{'diskused'};

            # /
            $root_node->{'user_contained_usage'} += $diskused;
            $root_node->{'/child_node_sizes'}    += $diskused;

            # /mail
            $mail_node->{'user_contained_usage'} += $diskused;
            $mail_node->{'/child_node_sizes'}    += $diskused;

            # /mail/domain
            $domain_mail_node->{'user_contained_usage'} += $diskused;
            $domain_mail_node->{'/child_node_sizes'}    += $diskused;

            # /mail/domain/user
            $domain_mail_node->{'/'}{$user} = _leaf_node_template($diskused);
        }
    }
    return;

}

sub _augment_contents_with_mail_archive_usage {
    my ($root_node) = @_;
    my $mail_node = $root_node->{'/'}{'mail'} or return;

    my $maildir               = "$Cpanel::homedir/mail";
    my $mail_archive_dir      = "$maildir/archive";
    my $archive_mail_dir_size = ( lstat($maildir) )[7] or return;
    my $mail_archive_node     = $mail_node->{'/'}{'archive'} = _node_template($archive_mail_dir_size);

    # /
    $root_node->{'user_contained_usage'} += $archive_mail_dir_size;
    $root_node->{'/child_node_sizes'}    += $archive_mail_dir_size;

    # /mail
    $mail_node->{'user_contained_usage'} += $archive_mail_dir_size;
    $mail_node->{'/child_node_sizes'}    += $archive_mail_dir_size;

    my $domain_archive_size;
    my $archive_domains_ar = eval { Cpanel::FileUtils::Dir::get_directory_nodes($mail_archive_dir); };
    if ($archive_domains_ar) {
        foreach my $domain (@$archive_domains_ar) {
            $domain_archive_size = Cpanel::LoadFile::loadfile("$mail_archive_dir/$domain/diskusage_total") || 0;

            # /
            $root_node->{'user_contained_usage'} += $domain_archive_size;
            $root_node->{'/child_node_sizes'}    += $domain_archive_size;

            # /mail
            $mail_node->{'user_contained_usage'} += $domain_archive_size;
            $mail_node->{'/child_node_sizes'}    += $domain_archive_size;

            # /mail/archive
            $mail_archive_node->{'user_contained_usage'} += $domain_archive_size;
            $mail_archive_node->{'/child_node_sizes'}    += $domain_archive_size;

            $mail_archive_node->{'/'}{$domain} = _leaf_node_template($domain_archive_size);
        }
    }

    return;
}

# A node that can have children
# We use these to build out the virtual mail/ and mail/archives
# directory as they may be located on a different server in future
# versions
sub _node_template {
    my ($size) = @_;
    return {
        '/size'                => $size,
        'traversible'          => 1,
        'owner'                => $Cpanel::user,
        '/type'                => 'dir',
        'user_contained_usage' => 0,
        '/child_node_sizes'    => 0,
    };
}

# A node that cannot have children
# We currently use this to represent
# an email account or a mail archive
# as a single unit
sub _leaf_node_template {
    my ($size) = @_;
    return {
        '/size'                => $MAIL_DIR_VSIZE,
        'traversible'          => 1,
        'owner'                => $Cpanel::user,
        '/type'                => 'dir',
        'user_contained_usage' => $size,,
        '/child_node_sizes'    => $size,,
    };
}

my $xss_checked_modify_none_allow_demo = {
    xss_checked => 1,
    modify      => 'none',
    allow_demo  => 1,
    needs_role  => 'FileStorage',
};

our %API = (
    fetch_raw_disk_usage     => $xss_checked_modify_none_allow_demo,
    fetchdiskusage           => $xss_checked_modify_none_allow_demo,
    fetchdiskusagewithextras => $xss_checked_modify_none_allow_demo,
    clearcache               => $xss_checked_modify_none_allow_demo,
    buildcache               => $xss_checked_modify_none_allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
