package Cpanel::Resolvers;

# cpanel - Cpanel/Resolvers.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Ips::Fetch ();

sub fetchresolvers {
    my @nameservers;
    if ( open my $res_fh, '<', '/etc/resolv.conf' ) {
        while ( my $line = readline $res_fh ) {
            chomp $line;
            next if $line !~ m/^\s*nameserver\s+(\S+)/;
            my $resolver = $1;
            $resolver =~ s/[;#].*$//;    # Trim possible EOL comments
            push @nameservers, $1;
        }
        close $res_fh;
    }
    return \@nameservers;
}

sub requires_caching_nameserver {
    my $local_ip_list = shift || Cpanel::Ips::Fetch::fetchipslist();
    $local_ip_list->{'127.0.0.1'} = 1;

    my $resolvers_ref = fetchresolvers();
    foreach my $resolver ( @{$resolvers_ref} ) {
        return 1 if ( $local_ip_list->{$resolver} );
    }
    return 0;
}

1;
