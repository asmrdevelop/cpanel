package Cpanel::cPCPAN::Installed;

# cpanel - Cpanel/cPCPAN/Installed.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub _make_ExtUtils_Installed {
    require ExtUtils::MakeMaker;
    require ExtUtils::Installed;
    my $prefix   = shift;
    my $location = shift;
    my $inst;
    local @INC = grep { !m/^\/scripts/ && !m/^\/usr\/local\/cpanel/ && !m/^\./ } @INC;

    if ($prefix) {
        my %TConfig = %ExtUtils::Installed::Config;
        if ( ( scalar keys %TConfig ) ) {
            require Config;
            my @inc_override = ();
            if ( $location && $location eq 'local::lib' ) {
                $TConfig{'archlibexp'}  = $prefix . '5/' . $Config::Config{'installstyle'} . '/' . $Config::Config{'archname'};
                $TConfig{'sitearchexp'} = $prefix . '5/' . $Config::Config{'installstyle'};
            }
            else {
                $TConfig{'archlibexp'}  = $prefix . $Config::Config{'archlibexp'};
                $TConfig{'sitearchexp'} = $prefix . $Config::Config{'sitearchexp'};
            }

            # User directories use lib, not lib64, even on 64-bit systems.
            my $homedir = ( getpwuid($>) )[7];
            if ( $prefix =~ /^\Q$homedir\E/ ) {
                foreach my $config (qw/archlibexp sitearchexp/) {
                    $TConfig{$config} =~ s/lib64/lib/;
                }
            }
            push @inc_override, $TConfig{'archlibexp'};
            push @inc_override, $TConfig{'sitearchexp'};
            untie %ExtUtils::Installed::Config;
            %ExtUtils::Installed::Config = %TConfig;
            $inst                        = ExtUtils::Installed->new(
                'config_override' => \%TConfig,
                'inc_override'    => \@inc_override,
            );
        }
        else {
            $inst = ExtUtils::Installed->new();
        }
        if ( exists $inst->{':private:'} ) {
            $inst->{':private:'}{'EXTRA'} = [$prefix];
        }
    }
    else {
        $inst = ExtUtils::Installed->new();
    }
    return $inst;
}

sub uninstall {
    my $self   = shift;
    my $mod    = shift;
    my $prefix = shift;

    my $found_files = 0;
    print "Processing Uninstall of $mod.\n";
    foreach my $mod_location ( _mod_locations() ) {
        my $inst = _make_ExtUtils_Installed( $prefix, $mod_location );

        my @files;
        eval { @files = $inst->files($mod); };
        next if !@files;

        $found_files = 1;

        foreach my $file ( sort(@files) ) {
            next if ( $file =~ /^\.+$/ );
            print "Uninstalling $file.\n";
            unlink $file;
        }
        my $packfile = $inst->packlist($mod)->packlist_file();
        print "Removing $packfile.\n";
        unlink $packfile;
        print "Uninstall of $mod complete.\n";
    }
    print "Uninstall of $mod failed (could not locate the packlist)\n" if !$found_files;
    return '';
}

sub list_installed {
    my $self   = shift;
    my $prefix = shift;

    my @ML;
    my $found = {};
    foreach my $mod_location ( _mod_locations() ) {
        my $inst = _make_ExtUtils_Installed( $prefix, $mod_location );
        foreach my $mod ( $inst->modules() ) {

            # avoid duplicate module
            next if $found->{$mod};
            $found->{$mod} = 1;
            my $ver = $inst->{$mod}{'version'};
            if ( !$ver ) {
                foreach my $file ( $inst->files($mod) ) {
                    next if ( $file !~ /\.pm$/ );
                    if ( -e $file ) {
                        $ver = MM->parse_version($file);
                        last if $ver && $ver ne 'undef';
                    }
                }
            }
            if ( $self->{'print'} ) {
                print $mod . '=' . $ver . "=\n";
            }
            else {
                push @ML, $mod . '=' . $ver . "=";
            }
        }
    }
    return \@ML;
}

sub _mod_locations {
    if ( $> == 0 ) { return ('default'); }
    return ( 'default', 'local::lib' );
}
1;
