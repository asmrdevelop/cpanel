package Cpanel::DiskCounter;

# cpanel - Cpanel/DiskCounter.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Chdir            ();
use Cpanel::Fcntl::Types     ();
use Cpanel::Fcntl::Constants ();
use Cpanel::PwCache          ();
use Cpanel::SafeFind         ();

my $APIref;

use constant S_IFDIR => $Cpanel::Fcntl::Constants::S_IFDIR;
use constant S_IFMT  => $Cpanel::Fcntl::Constants::S_IFMT;

our $WANT_FILES = 1;
our $NO_FILES   = 0;

our $WANT_MAIL = 0;
our $SKIP_MAIL = 1;

#run test suite before committing any changes to this function
#several optimizations in here
sub disk_counter {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $dir, $want_files, $prefix, $skip_mail ) = @_;
    local $SIG{__WARN__} = 'DEFAULT';
    local $0 = "$0 - calculating disk usage";

    $prefix ||= q{};

    my $user_uid = ( Cpanel::PwCache::getpwnam_noshadow($Cpanel::user) )[2];
    return if !defined($user_uid);

    my $chdir = Cpanel::Chdir->new( $dir, ( 'quiet' => 1 ) );

    my $file_types_ref = \%Cpanel::Fcntl::Types::FILE_TYPES;    # reference for quick lookup

    my ( $mode, $size, $traversible, $dir_node, $i, $dev, $inode, $devinode, $dir_mode, $node_uid, $dir_size );

    ( $dir_mode, $node_uid, $dir_size ) = ( lstat q{.} )[ 2, 4, 12 ];
    $dir_size *= 512;
    my $dir_type = $file_types_ref->{ $dir_mode & S_IFMT };

    my %cached_formats = ( $dir_mode => $dir_type );
    my %owner_cache;

    my $initial_user_contained_usage = ( $node_uid == $user_uid ) ? ( 0 - $dir_size ) : 0;

    my $rFileMap = {
        '/'                    => { $prefix => {}, },
        '/size'                => $dir_size,
        '/type'                => $dir_type,
        '/child_node_sizes'    => ( 0 - $dir_size ),
        'user_contained_usage' => $initial_user_contained_usage,
        'traversible'          => ( -x _ && ( $node_uid == $user_uid || -r _ ) ) ? 1 : 0,
        'owner'                => ( $owner_cache{$node_uid} ||= ( Cpanel::PwCache::getpwuid_noshadow($node_uid) // $node_uid ) ),
        'file_counts'          => {},
    };

    #to prevent adding hard links to usage totals twice
    my %devinode_containerdir;

    Cpanel::SafeFind::find(
        {
            'no_chdir' => 1,
            'wanted'   => sub {
                if ( $skip_mail && index( $File::Find::name, './mail/' ) == 0 ) {
                    $File::Find::prune = 1;
                    return;
                }

                $rFileMap->{'file_counts'}->{$File::Find::dir}++;
                ( $dev, $inode, $mode, $node_uid, $size ) = ( lstat($File::Find::name) )[ 0, 1, 2, 4, 12 ];

                #Add this node's size to parent nodes.
                #
                #Besides being faster, it's important to check for $size > 0
                #to preserve when /child_node_sizes is undef.
                #(Adding 0 would turn undef into 0.)
                # NOTE: directories must be explicitly checked for as they have an undefined #
                #   size across multiple filesystem types #
                if ( $size > 0 || $mode & S_IFDIR ) {
                    $size *= 512;
                    $devinode = "$dev $inode";

                    if ( exists $devinode_containerdir{$devinode} ) {
                        $i = 0;

                        #this is an edge case, so not optimizing
                        my $dirpath  = $devinode_containerdir{$devinode};
                        my @dirpaths = ref $dirpath ? @$dirpath : ($dirpath);
                        $dir_node = $rFileMap;
                        my ( @cur_dir_path, $joined_cur_dir_path, $already_added_to_this_dir );
                        foreach ( split m{/}, $File::Find::dir ) {
                            push @cur_dir_path, $_;
                            next if ++$i == 1;
                            $dir_node                  = $dir_node->{'/'}->{ $prefix . $_ };
                            $joined_cur_dir_path       = join( '/', @cur_dir_path );
                            $already_added_to_this_dir = grep m{\A\Q$joined_cur_dir_path\E(?:/|\z)}, @dirpaths;

                            if ( !$already_added_to_this_dir && $size ) {
                                $dir_node->{'/child_node_sizes'}    += $size;
                                $dir_node->{'user_contained_usage'} += $size if $node_uid == $user_uid;
                            }
                        }
                        if ( ref $dirpath ) {
                            push @{ $devinode_containerdir{$devinode} }, $File::Find::dir;
                        }
                        else {
                            $devinode_containerdir{$devinode} = [$File::Find::dir];
                        }
                    }
                    else {
                        $devinode_containerdir{$devinode} = $File::Find::dir;
                        $dir_node = $rFileMap;
                        $rFileMap->{'/child_node_sizes'} += $size;

                        if ( length $File::Find::dir == 1 ) {

                            # Handle '.'
                            if ( $node_uid == $user_uid ) {
                                $rFileMap->{'user_contained_usage'} += $size;
                            }
                        }
                        elsif ( $node_uid == $user_uid ) {
                            $rFileMap->{'user_contained_usage'} += $size;
                            foreach ( split m{/}, substr( $File::Find::dir, 2 ) ) {    # strip off ./
                                $dir_node = $dir_node->{'/'}->{ $prefix . $_ };
                                $dir_node->{'/child_node_sizes'}    += $size;
                                $dir_node->{'user_contained_usage'} += $size;
                            }
                        }
                        else {

                            #identical to the above except no ++user_contained_usage
                            foreach ( split m{/}, substr( $File::Find::dir, 2 ) ) {    # strip off ./
                                                                                       #  next if ( ++$i == 1 );
                                $dir_node = $dir_node->{'/'}->{ $prefix . $_ };
                                $dir_node->{'/child_node_sizes'} += $size;
                            }
                        }
                    }
                }

                if ( $mode & S_IFDIR ) {
                    $traversible = -x _ && ( $node_uid == $user_uid || -r _ );    #set this before calling getpwuid
                    $dir_node->{'/'}->{ $prefix . ( ( split( m{/}, $File::Find::name ) )[-1] // '' ) } = {
                        '/type' => $dir_type,
                        '/size' => $size,
                        'owner' => ( $owner_cache{$node_uid} ||= ( Cpanel::PwCache::getpwuid_noshadow($node_uid) // $node_uid ) ),
                        (
                            $traversible
                            ? (
                                '/'                    => {},
                                'traversible'          => 1,
                                '/child_node_sizes'    => 0,
                                'user_contained_usage' => 0,
                              )

                              #undef means that we have no way of knowing what the
                              #value actually is. We could populate '/' if the
                              #directory is readable and we $want_files, but
                              #there's no application-driven need for such yet.
                            : (
                                '/'                    => undef,
                                'traversible'          => 0,
                                '/child_node_sizes'    => undef,
                                'user_contained_usage' => undef,
                            )
                        ),
                    };
                }
                elsif ($want_files) {
                    $dir_node->{'/'}->{ $prefix . ( ( split( m{/}, $File::Find::name ) )[-1] // '' ) } = {
                        '/type' => ( $cached_formats{$mode} ||= $file_types_ref->{ $mode & S_IFMT } ),
                        '/size' => $size,
                        'owner' => ( $owner_cache{$node_uid} ||= ( Cpanel::PwCache::getpwuid_noshadow($node_uid) // $node_uid ) ),
                    };
                }
            },
        },
        q{.},
    );

    delete $rFileMap->{'/'}->{$prefix};

    return $rFileMap;
}

#transform the data so that we have a nicer, more API-like structure
sub api2_disk_counter {
    my %CFG = @_;
    my $dir = $CFG{'path'} || $Cpanel::homedir;

    $dir =~ s{/+\z}{};    #strip trailing /

    my $dc_data = disk_counter( $dir, $CFG{'want_files'}, $CFG{'prefix'}, $CFG{'skip_mail'} );

    my $base_dir_name = ( $dir =~ m{([^/]+)\z} ) && $1;

    return _disk_counter_result_xformer( $base_dir_name, $dc_data );    #mods in place
}

sub _disk_counter_result_xformer {
    my ( $name, $node ) = @_;

    $node->{'name'}  = $name;
    $node->{'usage'} = delete $node->{'/size'};
    $node->{'type'}  = delete $node->{'/type'};
    if ( exists $node->{'/child_node_sizes'} ) {
        $node->{'contained_usage'} = delete $node->{'/child_node_sizes'};
    }
    if ( exists $node->{'/'} ) {
        $node->{'contents'} = [ map { _disk_counter_result_xformer( $_, $node->{'/'}->{$_} ) } keys %{ $node->{'/'} } ];
        delete $node->{'/'};
    }

    return $node;
}

sub fetchnodes_bydepth {
    my $rFileMap     = shift;
    my $wanted_depth = shift;
    my %nodeList;

    fetchnodes_bydepth_r( \%nodeList, $rFileMap, $wanted_depth );
    wantarray ? return ( \%nodeList, $nodeList{'/child_node_sizes'} ) : return \%nodeList;
}

sub fetchnodes_bydepth_r {
    my $nodeList      = shift;
    my $rFileMap      = shift;
    my $wanted_depth  = shift;
    my $current_depth = shift || '0';
    my $curdir        = shift || '.';
    if ( $current_depth == $wanted_depth ) {
        $nodeList->{'/child_node_sizes'} += $rFileMap->{'/child_node_sizes'};
    }
    foreach my $node ( keys %{ $rFileMap->{'/'} } ) {
        if ( $current_depth == $wanted_depth ) {
            $nodeList->{ substr( $curdir . '/' . $node, 2 ) } = {
                '/child_node_sizes' => $rFileMap->{'/'}->{$node}->{'/child_node_sizes'} || $rFileMap->{'/'}->{$node}->{'/size'},
                '/size'             => $rFileMap->{'/'}->{$node}->{'/size'},
                '/type'             => $rFileMap->{'/'}->{$node}->{'/type'}
            };
        }
        elsif ( $rFileMap->{'/'}->{$node}->{'/type'} eq 'dir' ) {
            fetchnodes_bydepth_r( $nodeList, $rFileMap->{'/'}->{$node}, $wanted_depth, $current_depth + 1, $curdir . '/' . $node );
        }
    }
    return;
}

our %API = (
    'disk_counter' => {
        'xss_checked' => 1,
        'modify'      => 'none',
        allow_demo    => 1,
    },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
