package B::C::IsUsingModule;

my $use_all_required_modules = 1;

my @to_check;

sub import {
    my ( $package, @modules ) = @_;

    @to_check = @modules;
    return;
}

sub check_if_modules_are_in_inc {

    foreach my $m (@to_check) {
        next unless defined $m;
        my $path = $m . '.pm';
        $path =~ s{::}{/}g;
        if ( exists $INC{$path} ) {
            print "Using: $m\n";
        }
        else {
            $use_all_required_modules = 0;
        }
    }

    return $use_all_required_modules;
}

CHECK {    # weird but avoid parsing the command line output
    exit( check_if_modules_are_in_inc() ? 0 : 1 );
}

1;
