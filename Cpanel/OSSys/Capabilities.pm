package Cpanel::OSSys::Capabilities;

# cpanel - Cpanel/OSSys/Capabilities.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Logger ();
use Cpanel::IONice ();

my $FILE = '/var/cpanel/env_capabilities';

my %DETECTORS = (
    'ionice' => sub {
        return 1 if Cpanel::IONice::ionice( 'best-effort', 3 );
        return 0;
    }
);

my $logger = Cpanel::Logger->new();

sub load {
    my ($class) = @_;
    my %capabilities;

    open( my $fh, '<', $FILE ) or return bless {}, $class;

    while ( my $line = readline($fh) ) {
        chomp $line;

        $line =~ s/^\s*//g;
        $line =~ s/\s*$//g;

        next if $line =~ /^#/;

        my ( $key, $value ) = split /\s*=\s*/, $line;

        $capabilities{$key} = $value;
    }

    close $fh;

    return bless \%capabilities, $class;
}

sub save {
    my ( $class, $capabilities ) = @_;

    open( my $fh, '>', $FILE ) or $logger->die("Unable to open $FILE for writing: $!");

    print {$fh} "# env_capabilities -- List of system calls usable in current server environment\n";

    foreach my $capability ( sort keys %{$capabilities} ) {
        print {$fh} "$capability=$capabilities->{$capability}\n";
    }

    close $fh;

    return;
}

sub detect {
    my ($class) = @_;
    my %capabilities;

    foreach my $capability ( sort keys %DETECTORS ) {

        #
        # When detecting each capability, we must fork a subprocess to perform
        # the detection, which may have side effects in the current process,
        # which might not be desirable to the caller.
        #
        my $pid = fork();

        if ( !defined($pid) ) {
            $logger->die("Unable to fork(): $!");
        }
        elsif ( $pid == 0 ) {

            #
            # Exit 0 as per usual shell convention to indicate success, or "true"
            # state, that the capability was detected.
            #
            exit 0 if $DETECTORS{$capability}->();
            exit 1;
        }

        waitpid $pid, 0;

        $capabilities{$capability} = ( ( $? >> 8 ) == 0 ) ? 1 : 0;
    }

    return bless \%capabilities, $class;
}

sub capable_of {
    my ( $self, $capability ) = @_;

    #
    # By default, if a capability is not listed in the capabilities hash in any
    # way, return true, indicating that the capability is present on the system,
    # regardless of whether or not it actually does.  This is useful in the
    # scenario where, for some reason or another, /var/cpanel/env_capabilities
    # is not present and populated, and this method is used to check for a system
    # capability prior to performing an action pertinent to said capability; the
    # code querying for said capability would still proceed to attempt to execute
    # the code contingent upon the capability, at least.
    #
    return 1 unless exists $self->{$capability};
    return 1 if $self->{$capability};

    return 0;
}

1;
