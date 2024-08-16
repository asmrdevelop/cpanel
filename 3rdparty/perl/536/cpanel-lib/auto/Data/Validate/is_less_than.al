# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 560 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/is_less_than.al)"
# -------------------------------------------------------------------------------


sub is_less_than{	
	my $self = shift if ref($_[0]);
	my $value = shift;
	my $threshold = shift;
		
	# must be a number
	my $untainted = is_numeric($value);
	return unless defined($untainted);
	
	# threshold must be defined
	return unless defined $threshold;
	
	return unless $value < $threshold;
		
	return $untainted;
}

# end of Data::Validate::is_less_than
1;
