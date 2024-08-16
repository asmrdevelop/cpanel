package Cpanel::iContact::EventImportance;

# cpanel - Cpanel/iContact/EventImportance.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#This object retrieves event importances as stored in a datastore.
#The details of that storage are abstracted from the caller.
#
#This module is the "successor" to the /var/cpanel/iclevels.conf file.
#It will actually import that file's contents on initial load.
#
#A big added feature here is the idea of individual events having importance
#settings. As of 11.48 there is no UI or API for setting those, but such
#will likely be part of a future release.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Transaction::File::JSONReader     ();    # PPI USE OK -- used in new via __TRANSACTION_CLASS
use Cpanel::iContact::EventImportance::Legacy ();

# This is the authoritative file for all contact levels
our $_datastore_file = '/var/cpanel/icontact_event_importance.json';

our %NAME_TO_NUMBER = (
    'High'     => 1,
    'Medium'   => 2,
    'Low'      => 3,
    'Disabled' => 0,
);

our $DEFAULT_IMPORTANCE = $NAME_TO_NUMBER{'Low'};

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;

    my $trans_class = $self->__TRANSACTION_CLASS();
    $self->{'_trans'} = $trans_class->new( path => $_datastore_file );

    $self->{'_data'} = $self->{'_trans'}->get_data();

    #If the file was empty (e.g., this is a new datastore), then what we'll
    #get is a scalar ref to undef. That's useless, and this isn't really an
    #error condition, so silently mask it.
    if ( 'SCALAR' eq ref $self->{'_data'} ) {
        $self->{'_data'} = {};

        $self->_init_data_from_legacy();
    }

    $self->_ensure_that_defaults_are_there();

    return $self;
}

#----------------------------------------------------------------------
#Subclass interface

sub __TRANSACTION_CLASS {
    return 'Cpanel::Transaction::File::JSONReader';
}

#----------------------------------------------------------------------

#The timestamp of the datastore when it was originally read in.
#
sub get_mtime {
    my ($self) = @_;

    return $self->{'_trans'}->get_original_mtime();
}

#The logic for determining an event’s importance is:
#
#1) Each individual event can have its own importance setting.
#If set, this is always used.
#
#2) Any event without its own setting will receive the application’s
#default setting, if set.
#
#3) If the application has no default, then return $DEFAULT_IMPORTANCE.
#
sub get_event_importance {
    my ( $self, $app, $event ) = @_;

    my $data = $self->{'_data'};

    return $DEFAULT_IMPORTANCE if !$data->{$app};

    return $data->{$app}{$event} if length $event && exists $data->{$app}{$event};

    return $data->{$app}{'*'};
}

#Same logic as get_event_importance(), but skip step 1.
#
sub get_application_importance {
    my ( $self, $app ) = @_;

    return $self->get_event_importance( $app, '*' );
}

sub get_all_contact_importance {
    my ($self) = @_;

    my @importance;
    my %number_to_name = reverse %NAME_TO_NUMBER;
    foreach my $app ( sort keys %{ $self->{'_data'} } ) {
        foreach my $event ( sort keys %{ $self->{'_data'}{$app} } ) {
            my $number = $self->{'_data'}{$app}{$event};
            push @importance, { 'app' => $app, 'event' => $event, 'importance' => $number, 'name' => $number_to_name{$number} };
        }

    }
    return \@importance;
}

#----------------------------------------------------------------------
#NOTE: These methods eschew the normal fallback mechanism for queries
#and thus are probably only useful for something that needs to present
#the object's state well enough to facilitate editing.
#
#These methods are on the reader object because such an application
#will probably not query and set the settings in the same process: the
#first session will be a reader (i.e., to present the settings to the user),
#then the second will be a writer.
#
sub get_application_importance_setting {
    my ( $self, $app ) = @_;

    return $self->get_event_importance_setting( $app, '*' );
}

sub get_event_importance_setting {
    my ( $self, $app, $event ) = @_;

    my $data = $self->{'_data'};

    #This works because $data->{$app} will either be a hashref or undef.
    #
    return $data->{$app} && $data->{$app}{$event};
}

#----------------------------------------------------------------------

sub _ensure_that_defaults_are_there {
    my ($self) = @_;

    my ( $high_importance, $medium_importance, $low_importance, $disabled ) = map { $NAME_TO_NUMBER{$_} } qw( High Medium Low Disabled );

    #
    # When adding new defaults, we follow the following pattern
    # Needs action ASAP - High
    # Needs action Sometime - Medium
    # No Action - Low
    #
    my %default = (
        'Accounts'                             => $low_importance,
        'Accounts::ChildDedistributionFailure' => $high_importance,
        'Accounts::ChildDedistributionSuccess' => $low_importance,
        'Accounts::ChildDistributionFailure'   => $high_importance,
        'Accounts::ChildDistributionSuccess'   => $low_importance,
        'Accounts::ChildRedistributionFailure' => $high_importance,
        'Accounts::ChildRedistributionSuccess' => $low_importance,
        'AdminBin'                             => $low_importance,
        'Backup'                               => $medium_importance,
        'Backup::Delayed'                      => $high_importance,
        'Backup::Disabled'                     => $high_importance,
        'Backup::Failure'                      => $high_importance,
        'Backup::PreBackupNotice'              => $low_importance,
        'Backup::Success'                      => $low_importance,
        'Backup::Transport'                    => $high_importance,
        'BandwidthUsageExceeded'               => $medium_importance,
        'ChangePassword'                       => $low_importance,
        'Check'                                => $low_importance,
        'Check::Biglog'                        => $high_importance,
        'Check::CpanelPackages'                => $high_importance,
        'Check::EximConfig'                    => $high_importance,
        'Check::Hack'                          => $high_importance,
        'Check::IP'                            => $high_importance,
        'Check::ImmutableFiles'                => $high_importance,
        'Check::InvalidDomains'                => $medium_importance,
        'Check::MySQL'                         => $high_importance,
        'Check::MysqlConnection'               => $high_importance,
        'Check::Oops'                          => $high_importance,
        'Check::SSLCertExpired'                => $high_importance,
        'Check::SSLCertExpiresSoon'            => $medium_importance,
        'Check::Smart'                         => $high_importance,
        'Check::ValidServerHostname'           => $high_importance,
        'Check::UnmonitoredEnabledServices'    => $high_importance,
        'Check::SecurityAdvisorStateChange'    => $high_importance,
        'Check::HostnameOwnedByUser'           => $high_importance,
        'Check::Resolvers'                     => $high_importance,
        'Check::PdnsConf'                      => $medium_importance,
        'Check::LocalConfTemplate'             => $medium_importance,
        'CloudLinux'                           => $medium_importance,
        'Config'                               => $high_importance,
        'ConvertAddon'                         => $high_importance,
        'DemoMode'                             => $high_importance,
        'Deprecated::API1'                     => $medium_importance,
        'Deprecated::EA3RPMs'                  => $medium_importance,
        'DigestAuth'                           => $medium_importance,
        'DnsAdmin'                             => $medium_importance,
        'DnsAdmin::ClusterError'               => $medium_importance,
        'DnsAdmin::UnreachablePeer'            => $high_importance,
        'DnsAdmin::DnssecError'                => $medium_importance,
        'Mail::ReconfigureCalendars'           => $high_importance,
        'Solr::Maintenance'                    => $medium_importance,
        'EasyApache'                           => $high_importance,
        'EasyApache::EA4_TemplateCheckUpdated' => $high_importance,
        'EasyApache::EA4_ConflictRemove'       => $high_importance,
        'Greylist'                             => $low_importance,
        'Install'                              => $low_importance,
        'Install::CheckcPHulkDB'               => $medium_importance,
        'Install::PackageExtension'            => $low_importance,
        'Install::FixcPHulkConf'               => $low_importance,
        'Install::CheckRemoteMySQLVersion'     => $low_importance,
        'Logd'                                 => $low_importance,
        'Logger'                               => $low_importance,
        'Notice'                               => $low_importance,
        'OutdatedSoftware::Notify'             => $medium_importance,
        'OverLoad::CpuWatch'                   => $medium_importance,
        'OverLoad::LogRunner'                  => $medium_importance,
        'Quota'                                => $low_importance,
        'Quota::Broken'                        => $high_importance,
        'Quota::DiskWarning'                   => $low_importance,
        'Quota::MailboxWarning'                => $low_importance,
        'Quota::RebootRequired'                => $medium_importance,
        'Quota::SetupComplete'                 => $low_importance,
        'RPMVersions'                          => $high_importance,
        'StuckScript'                          => $high_importance,
        'TwoFactorAuth::UserEnable'            => $low_importance,
        'TwoFactorAuth::UserDisable'           => $low_importance,
        'Update'                               => $high_importance,
        'Update::Blocker'                      => $high_importance,
        'Update::ServiceDeprecated'            => $high_importance,
        'Update::Now'                          => $high_importance,
        'appconfig'                            => $low_importance,
        'cPHulk'                               => $low_importance,
        'cPHulk::BruteForce'                   => $low_importance,
        'cPHulk::Login'                        => $low_importance,
        'chkservd'                             => $high_importance,
        'chkservd::DiskUsage'                  => $high_importance,
        'chkservd::Hang'                       => $high_importance,
        'chkservd::OOM'                        => $high_importance,
        'MailServer::OOM'                      => $medium_importance,
        'Mail::SpammersDetected'               => $disabled,
        'SSL::CertificateExpiring'             => $medium_importance,
        'SSL::LinkedNodeCertificateExpiring'   => $high_importance,
        'SSL::CheckAllCertsWarnings'           => $medium_importance,
        'Monitoring::SignupComplete'           => $low_importance,

        # In order to accommodate the consolidation control of
        # AutoSSL::CertificateExpiring from notify_expiring_certificates
        # into autossl, these three can now go to user AND/OR root:
        'AutoSSL::CertificateExpiring'         => $low_importance,
        'AutoSSL::CertificateExpiringCoverage' => $low_importance,
        'AutoSSL::CertificateRenewalCoverage'  => $low_importance,

        'AutoSSL::CertificateInstalled'                 => $low_importance,
        'AutoSSL::CertificateInstalledReducedCoverage'  => $high_importance,
        'AutoSSL::CertificateInstalledUncoveredDomains' => $medium_importance,

        'AutoSSL::DynamicDNSNewCertificate' => $medium_importance,

        # only go to the user and not root so they should not be in this list
        'Mail::ClientConfig'        => $low_importance,
        'Mail::HourlyLimitExceeded' => $low_importance,
        'Mail::SendLimitExceeded'   => $low_importance,
        'cpbackup'                  => $medium_importance,
        'cpbackupdisabled'          => $high_importance,
        'iContact'                  => $medium_importance,
        'installbandwidth'          => $high_importance,
        'killacct'                  => $low_importance,
        'parkadmin'                 => $low_importance,
        'queueprocd'                => $high_importance,
        'rpm.versions'              => $high_importance,
        'suspendacct'               => $low_importance,
        'sysup'                     => $high_importance,
        'unsuspendacct'             => $low_importance,
        'upacct'                    => $low_importance,
        'upcp'                      => $high_importance,
        'wwwacct'                   => $low_importance,
        'Stats'                     => $medium_importance,

        #High importance because there’s money involved!
        'Market' => $high_importance,

        #This is of high importance because it’s unexpected enough
        #that we don’t have a specific error message for it but
        #significant enough that it’s worth reporting. This would be
        #for unusual things like root being unable to create a file:
        #as a development-cost consideration it’s not worth having a
        #separate notification type for it, but it’s definitely worth
        #checking for and reporting regardless.
        'Application' => $high_importance,
    );

    my $self_data_hr = $self->{'_data'};

    for my $key ( keys %default ) {
        my ( $namespace, $notification ) = split( m{::}, $key );
        $notification ||= '*';
        if ( !defined $self_data_hr->{$namespace}{$notification} ) {
            $self_data_hr->{$namespace}{$notification} = $default{$key};
        }
    }

    my %event_importances = (
        cPHulk => {

            #If upgrading from something that only had cPHulk::* set,
            #and that setting was not 1, we should create a high-priority
            #default setting for root logins.
            Login => $high_importance,
        },
    );

    return 1;
}

sub _init_data_from_legacy {
    my ($self) = @_;

    my $legacy_data_hr = Cpanel::iContact::EventImportance::Legacy::get_data_struct_from_legacy();

    for my $app ( keys %$legacy_data_hr ) {

        #NOTE: This is unvalidated data that we ideally would be setting
        #via the methods in the "Write" subclass in order to validate; however,
        #to preserve backward compatibility we can just assign "blindly" here.
        $self->{'_data'}{$app}{'*'} = $legacy_data_hr->{$app};
    }

    return;
}

1;
