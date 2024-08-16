package Whostmgr::DNS::Trace;

# cpanel - Whostmgr/DNS/Trace.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Sys::Hostname         ();
use Cpanel::DnsUtils::AskDnsAdmin ();
use Tree::MultiNode               ();    #includes Tree::MultiNode::Handle

# Returns a Tree::MultiNode::Handle object
sub get_peer_tree {
    my $cluster_user = shift || $ENV{'REMOTE_USER'};
    my $tree         = Tree::MultiNode->new();
    my $handle       = Tree::MultiNode::Handle->new($tree);

    my $hostname = Cpanel::Sys::Hostname::gethostname();
    $handle->set_key($hostname);

    my $getpath;
    {
        local $ENV{'REMOTE_USER'} = $cluster_user;

        # TODO: askdnsadmin should take the user as an argument instead of
        # reading $ENV{'REMOTE_USER'}
        $getpath = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin("GETPATH");
    }
    my @PATH = split( /\n/, $getpath );

    my ( $key, $val );
    foreach my $path (@PATH) {
        next if $path !~ m{\S};
        $handle->top();

        chomp $path;
        my ( $master, $slave ) = split( m{\s+}, $path );
        my $hhandle = _find_node( $slave, $handle ) || $handle;

        if ( defined $hhandle ) {
            ( $key, $val ) = $hhandle->get_data();
        }

        if ( $key ne $slave ) {
            $hhandle = _find_node( $master, $handle ) || $handle;
            $hhandle->add_child($slave);
        }
    }

    $handle->top();
    return $handle;
}

sub _find_node {
    my ( $node, $handle ) = @_;
    my ( $key, $val );

    ( $key, $val ) = $handle->get_data();

    return if $key eq $node;

    my $i;
    for ( $i = 0; $i < scalar( $handle->children ); ++$i ) {
        $handle->down($i);
        my $result = _find_node( $node, $handle );
        return if !defined($result);
        $handle->up();
    }

    return $handle;
}

1;
