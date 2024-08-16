#!/usr/local/cpanel/3rdparty/bin/perl

# Copyright 2023 cPanel, L.L.C. - All rights reserved.
# copyright@cpanel.net
# https://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package scripts::modify_default_featurelist_entry;

use cPstrict;

=encoding utf-8

=head1 NAME

modify_default_featurelist_entry.pl

=head1 USAGE

    modify_default_featurelist_entry.pl [--feature <feature-name> | --help]

=head1 DESCRIPTION

This script modifies all feature lists - except the disabled list - to
enable or disable a certain feature. Currently disables the feature
on cPanel versions 110 and below, and enables the feature on cPanel
versions 116 and above using a do_once method.

=head1 METHODS

=cut

use Cpanel::ConfigFiles          ();
use Cpanel::Features::Load       ();
use Cpanel::Features::Write      ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::Imports;
use Cpanel::Version          ();
use Cpanel::Version::Compare ();

use parent qw( Cpanel::HelpfulScript );

use constant _OPTIONS => ('feature=s');

our $VERSION_DIR = "/var/cpanel/version";

__PACKAGE__->new(@ARGV)->run() if !caller;

sub _verify_directories () {

    if ( !-e $Cpanel::ConfigFiles::FEATURES_DIR ) {
        mkdir( $Cpanel::ConfigFiles::FEATURES_DIR, 0755 ) or do {
            logger()->warn("Unable to create feature directory '$Cpanel::ConfigFiles::FEATURES_DIR': $!");
            return;
        };
    }

    Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/features/default') if !-e '/var/cpanel/features/default';

    return 1;
}

=head2 modify_feature_for_all_feature_lists()

Adds a feature and value to all feature lists.

=cut

sub modify_feature_for_all_feature_lists ( $key, $value ) {

    _verify_directories();

    opendir( my $dh, $Cpanel::ConfigFiles::FEATURES_DIR ) || do {
        logger()->warn("Cannot open directory: $Cpanel::ConfigFiles::FEATURES_DIR.");
        return;
    };
    my @feature_lists = grep { !/^(\.\.?|disabled)$/n } readdir($dh);
    closedir($dh) or die $!;

    foreach my $feature_list (@feature_lists) {
        my $features = eval { Cpanel::Features::Load::load_featurelist($feature_list) };
        if ( my $error = $@ ) {
            logger()->warn("Unable to add default feature entry $key=$value: $@");
        }
        $features->{$key} = $value;
        Cpanel::Features::Write::write_featurelist( $feature_list, $features );
    }

    return 1;
}

=head2 do_once()

Creates a touch file to track whether a task has been done.
The task is executed and as long as the touch file exists,
it will not do it again.

=cut

sub do_once (%opts) {

    return unless $opts{version} && $opts{code} && ref $opts{code} eq 'CODE';

    my $lock = _lock_name(%opts);
    return if -e $lock;

    _mark_did_once(%opts);

    my $ret = eval { $opts{code}->(); };

    warn($@) if $@;

    return $ret;
}

sub _mark_did_once (%opts) {

    my $lock = _lock_name(%opts);

    if ( !Cpanel::FileUtils::TouchFile::touchfile($lock) ) {
        warn("Failed to touch cpanel $opts{version} version file");
    }
    return 1;
}

sub _lock_name (%opts) {
    return $VERSION_DIR . '/cpanel' . $opts{version};
}

=head2 I<OBJ>->run()

Runs this script.

=cut

sub run ($self) {
    my $feature = $self->getopt('feature') || die $self->full_help();

    my $version = Cpanel::Version::getversionnumber();
    my $is_110  = Cpanel::Version::Compare::compare_major_release( $version, '<=', '11.110' );
    my $is_116  = Cpanel::Version::Compare::compare_major_release( $version, '>=', '11.116' );

    if ($is_110) {
        do_once(
            'version' => "11.110_disable_sitejet",
            'eol'     => 'never',
            'code'    => sub { modify_feature_for_all_feature_lists( $feature, '0' ) },
        );
    }

    if ($is_116) {
        do_once(
            'version' => "11.116_enable_sitejet",
            'eol'     => 'never',
            'code'    => sub { modify_feature_for_all_feature_lists( $feature, '1' ) },
        );
    }
}

1;
