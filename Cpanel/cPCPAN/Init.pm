package Cpanel::cPCPAN;

# cpanel - Cpanel/cPCPAN/Init.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub init_cfg {
    if ( $> != 0 ) {
        my $self = shift;
        require Data::Dumper;
        eval "require CPAN::Config";
        require Cpanel::cPCPAN::Config;    # PPI USE OK - provide fetch_config
        require Cpanel::PwCache;
        require Config;
        local $Data::Dumper::Useqq = 1;
        local $Data::Dumper::Terse = 1;

        my $homedir = ( Cpanel::PwCache::getpwuid($>) )[7];

        # Setup home/perl5 for local::lib
        mkdir( $homedir . '/perl', 0755 ) if ( !-e $homedir . '/perl' );
        my $linked_path = 'perl/' . $Config::Config{'prefix'};
        $linked_path =~ s/\/+/\//g;
        if ( !-e $homedir . '/' . $linked_path ) {
            require Cpanel::SafeDir::MK;
            Cpanel::SafeDir::MK::safemkdir( $homedir . '/' . $linked_path, '0755' );
        }
        if ( !-d $homedir . '/perl5' || ( -l $homedir . '/perl5' && readlink( $homedir . '/perl5' ) ne $linked_path ) ) {
            rename( $homedir . '/perl5', $homedir . '/perl5.bak.' . time() );
            symlink $linked_path, $homedir . '/perl5';
        }
        my @checkdirs = ($homedir);
        if ( $self->{'basedir'} ne $homedir ) { push @checkdirs, $self->{'basedir'}; }
        foreach my $basedir (@checkdirs) {
            mkdir( $basedir . '/.cpan',       0700 );
            mkdir( $basedir . '/.cpan/CPAN/', 0700 );
            my $MyConfig = $self->fetch_config( 'prefer_cache' => 1 );
            _mergeconfig( $MyConfig, $CPAN::Config );
            if ( open my $my_cf_fh, '>', $basedir . '/.cpan/CPAN/MyConfig.pm' ) {
                print {$my_cf_fh} '$CPAN::Config = ' . Data::Dumper::Dumper($MyConfig) . ';' . "\n";
                print {$my_cf_fh} "1;\n__END__\n";
                close $my_cf_fh;
            }
            else {
                warn "Failed to update $basedir/.cpan/CPAN/MyConfig.pm: $!";
            }
        }
    }
}

1;
