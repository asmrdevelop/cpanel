# NOTE: Derived from blib/lib/Data/Validate.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package Data::Validate;

#line 882 "blib/lib/Data/Validate.pm (autosplit into blib/lib/auto/Data/Validate/length_is_between.al)"
# -------------------------------------------------------------------------------


sub length_is_between{
	my $self = shift if ref($_[0]);
	my $value = shift;
	my $min = shift;
	my $max = shift;
	
	return unless defined($value);
	
	if(defined($min)){
		return unless length($value) >= $min;
	}
	
	if(defined($max)){
		return unless length($value) <= $max;
	}
	
	return $value;
	
}

1;
# end of Data::Validate::length_is_between
