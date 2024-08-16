package Install::DefaultFeatureFiles;

# cpanel - install/DefaultFeatureFiles.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Features         ();
use Cpanel::Features::Load   ();
use Cpanel::Features::Lists  ();
use Cpanel::FileUtils::Chown ();
use Cpanel::ConfigFiles      ();

use base qw( Cpanel::Task );

our $VERSION = '1.0';

=head1 DESCRIPTION

    Create feature list directory and create default files (adjust their permissions):
    - default
    - disabled
    - 'Mail Only'

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my ($class) = @_;
    my $self = $class->SUPER::new();

    $self->set_internal_name('default_feature_files');

    return $self;
}

sub _create_mail_only_feature_list {

    # Re-create the 'Mail Only' feature list everytime
    # we have a cpanel update.
    #
    # This ensures that the 'Mail Only' featurelist is up to date,
    # without the need to explicitly disable newly-added features each time.
    my %new_features = Cpanel::Features::Load::load_featurelist('Mail Only');
    foreach my $feature ( Cpanel::Features::get_default_mail_only_features() ) {

        # If a 'Mail Only' feature has been disabled by the admin,
        # then keep it disabled.
        next if exists $new_features{$feature} && !$new_features{$feature};
        $new_features{$feature} = 1;
    }

    Cpanel::Features::save_featurelist( "Mail Only", \%new_features, 1, 1 );
    return 1;

}

sub perform {
    my $self = shift;

    my $features_dir = $Cpanel::Features::Load::feature_list_dir;

    return 1 if $self->dnsonly();

    if ( !eval { Cpanel::Features::Lists::ensure_featurelist_dir(); return 1; } ) {
        warn "Unable to create feature directory '$Cpanel::ConfigFiles::FEATURES_DIR': $@";
        return;
    }

    my @files = map { "$features_dir/$_" } ( 'default', 'disabled', 'Mail Only' );
    for my $file (@files) {

        Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(
            'uid'         => 0,
            'gid'         => 0,
            'octal_perms' => 0644,
            'path'        => $file,
            'create'      => 1,
        );
    }

    _create_mail_only_feature_list();

    return 1;
}

1;

__END__
