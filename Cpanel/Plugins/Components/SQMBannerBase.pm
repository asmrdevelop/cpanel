package Cpanel::Plugins::Components::SQMBannerBase;

use Moo;
use cPstrict;

extends 'Cpanel::Plugins::Components::Base';

has 'feature_flag' => (
    is => 'ro',
);

has '+name' => (
    is      => 'ro',
    default => "SQM-Banner",
);

has '+description' => (
    is      => 'ro',
    default => 'A Banner for Site Quality Monitoring.',
);

has '+is_enabled' => (
    is      => 'ro',
    lazy    => 1,
    default => sub ($self) {
        require Cpanel::Features::Check;
        return 0 if !Cpanel::Features::Check::check_feature_for_user( $Cpanel::user, 'koality' );

        # These are negative flags, so the banner is disabled if the flag exists.
        {
            local $@;
            eval { require Cpanel::FeatureFlags };
            if ($@) {

                # This is on a cPanel version that does not have Cpanel::FeatureFlags.
                # We will check the for the flag directly.
                return 0 if -e "/var/cpanel/feature-flags/" . $self->feature_flag();
            }
            else {
                return 0 if Cpanel::FeatureFlags::is_feature_enabled( $self->feature_flag() );
            }
        }

        return 1;
    },
);

1;
