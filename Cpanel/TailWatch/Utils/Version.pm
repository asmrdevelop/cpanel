package Cpanel::TailWatch::Utils::Version;

# cpanel - Cpanel/TailWatch/Utils/Version.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

1;

package Cpanel::TailWatch;

sub version {
    my ( $self, $long ) = @_;
    print "Cpanel::TailWatch v$Cpanel::TailWatch::VERSION\n";

    if ($long) {
        chdir('/usr/local/cpanel');

        if ( opendir( my $tail_dir, '/usr/local/cpanel/Cpanel/TailWatch' ) ) {
            while ( my $file = readdir($tail_dir) ) {
                next if ( $file !~ /\.pm$/ );
                my @pb  = split( /\//, $file );
                my $mod = pop(@pb);
                $mod =~ s/\.pm$//g;

                my $ns  = 'Cpanel::TailWatch::' . $mod;
                my $req = 'Cpanel/TailWatch/' . $file;
                if ( eval q{require $req} ) {
                    if ( my $cr = $ns->can('is_enabled') ) {
                        my $on = $cr->( $ns, $self ) || 0;
                        if ($on) {
                            my $vers = $ns->VERSION || 'n/a';
                            push @{ $self->{'register_module'} }, [ $ns, $vers ];
                        }
                    }
                }
            }
            closedir($tail_dir);
        }
        else {
            print "Could not open directory \"/usr/local/cpanel/Cpanel/TailWatch\" : $! \n";
            exit;
        }

        foreach my $rm ( @{ $self->{'register_module'} } ) {
            print "  Active Driver $rm->[0] v$rm->[1]\n";
        }
    }
}

1;
