package App::Yath::Plugin::filter_by_test_tag;

# cpanel - App/Yath/Plugin/filter_by_test_tag.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'App::Yath::Plugin';

=head1 NAME

App::Yath::Plugin::filter_by_test_tag - yath plugin that filters tests by tag

=head1 SYNOPSIS

In the relevant test file:

    # HARNESS-META test-tag your-test-tag

From your shell (e.g. bash):

    export CP_TEST_TAG=your-test-tag

Invoke yath with the -p option:

    yath -p=filter_by_test_tag ...

In addition, tests can be mass tagged via an appropriately named file in the
/ULC/build-tools/test-tag/ directory (see the test-infra file for an example).

=head1 DESCRIPTION

A yath plugin that filters tests on a desired tag, matching with zero or more
tag annotations in individual test files.

=head1 METHODS

=over

=item B<sort_files>

Class method: yath plugin hook point. Given an array of Test2::Harness::TestFile objects.

Additionally, retrieves from the shell environment the test tag for the yath run.

If there is no test tag in the shell environment, no filtering occurs.

=back

=cut

sub sort_files {
    my ( $class, @tests ) = @_;

    # if there is not a specified tags, run all tests
    my $desired_tag = $ENV{'CP_TEST_TAG'} || '';
    unless ($desired_tag) {
        return @tests;
    }

    my @relevant_tests;
    my $matcher = _get_matcher($desired_tag);
    for my $test (@tests) {
        my @tags = $test->meta('test-tag');
        if ( $matcher->matches($test) ) {
            push( @relevant_tests, $test );
        }
    }
    return @relevant_tests;
}

sub _get_matcher {
    my ($desired_tag) = @_;
    my ($lookup_tag)  = ( $desired_tag =~ m/^!?(.*)/ );
    my $fname         = "/usr/local/cpanel/build-tools/test-tag/$lookup_tag";
    my $matcher;
    if ( -e $fname ) {
        $matcher = _tag_file_matcher->new( desired_tag => $desired_tag );
    }
    else {
        $matcher = _test_file_matcher->new( desired_tag => $desired_tag );
    }
    return $matcher;
}

package _test_file_matcher {
    use Moo;
    has 'desired_tag' => (
        is => 'ro',
    );

    sub matches {
        my ( $self, $test ) = @_;

        my $boolean     = 0;
        my $desired_tag = $self->desired_tag();
        if ( !defined($desired_tag) || $desired_tag =~ m/^\s*$/ ) {
            $boolean = 1;
        }
        else {
            my @test_tags = $test->meta('test-tag');
            my ($actual_desired_tag) = ( $desired_tag =~ m/^!?(.*)$/ );
            $boolean = grep { $_ eq $actual_desired_tag } @test_tags;
            if ( $desired_tag =~ m/^!/ ) {
                $boolean = !$boolean;
            }
        }
        return $boolean;
    }
}

package _tag_file_matcher {
    use Moo;
    has 'desired_tag' => (
        is => 'ro',
    );
    has 'tests' => (
        is      => 'ro',
        builder => \&_build_tests,
    );

    sub _build_tests {
        my ($self)       = @_;
        my $desired_tag  = $self->desired_tag();
        my ($lookup_tag) = ( $desired_tag =~ m/^!?(.*)/ );

        my %tests;
        my $fname = "/usr/local/cpanel/build-tools/test-tag/$lookup_tag";
        open( my $fh, '<', $fname ) or die "Could not open $fname";
        while ( my $line = <$fh> ) {
            next if $line =~ m/^\s*#/;
            next if $line =~ m/^\s*$/;
            chomp($line);
            $tests{$line} = 1;
        }
        return \%tests;
    }

    sub matches {
        my ( $self, $test ) = @_;

        my $tagged_tests = $self->tests();
        my $boolean      = exists $tagged_tests->{ $test->relative() };
        if ( $self->desired_tag() =~ m/^!/ ) {
            $boolean = !$boolean;
        }
        return $boolean;
    }
}

1;
