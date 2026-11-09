// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FileDetailSectionDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileDetailSectionDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'FileDetailSectionDto()';
}


}

/// @nodoc
class $FileDetailSectionDtoCopyWith<$Res>  {
$FileDetailSectionDtoCopyWith(FileDetailSectionDto _, $Res Function(FileDetailSectionDto) __);
}


/// Adds pattern-matching-related methods to [FileDetailSectionDto].
extension FileDetailSectionDtoPatterns on FileDetailSectionDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FileDetailSectionDto_Available value)?  available,TResult Function( FileDetailSectionDto_Restricted value)?  restricted,TResult Function( FileDetailSectionDto_Unsupported value)?  unsupported,TResult Function( FileDetailSectionDto_NotFound value)?  notFound,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FileDetailSectionDto_Available() when available != null:
return available(_that);case FileDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case FileDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case FileDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FileDetailSectionDto_Available value)  available,required TResult Function( FileDetailSectionDto_Restricted value)  restricted,required TResult Function( FileDetailSectionDto_Unsupported value)  unsupported,required TResult Function( FileDetailSectionDto_NotFound value)  notFound,}){
final _that = this;
switch (_that) {
case FileDetailSectionDto_Available():
return available(_that);case FileDetailSectionDto_Restricted():
return restricted(_that);case FileDetailSectionDto_Unsupported():
return unsupported(_that);case FileDetailSectionDto_NotFound():
return notFound(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FileDetailSectionDto_Available value)?  available,TResult? Function( FileDetailSectionDto_Restricted value)?  restricted,TResult? Function( FileDetailSectionDto_Unsupported value)?  unsupported,TResult? Function( FileDetailSectionDto_NotFound value)?  notFound,}){
final _that = this;
switch (_that) {
case FileDetailSectionDto_Available() when available != null:
return available(_that);case FileDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case FileDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case FileDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<FileDescriptorDto> value)?  available,TResult Function( String reason)?  restricted,TResult Function( String reason)?  unsupported,TResult Function( String reason)?  notFound,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FileDetailSectionDto_Available() when available != null:
return available(_that.value);case FileDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case FileDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case FileDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<FileDescriptorDto> value)  available,required TResult Function( String reason)  restricted,required TResult Function( String reason)  unsupported,required TResult Function( String reason)  notFound,}) {final _that = this;
switch (_that) {
case FileDetailSectionDto_Available():
return available(_that.value);case FileDetailSectionDto_Restricted():
return restricted(_that.reason);case FileDetailSectionDto_Unsupported():
return unsupported(_that.reason);case FileDetailSectionDto_NotFound():
return notFound(_that.reason);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<FileDescriptorDto> value)?  available,TResult? Function( String reason)?  restricted,TResult? Function( String reason)?  unsupported,TResult? Function( String reason)?  notFound,}) {final _that = this;
switch (_that) {
case FileDetailSectionDto_Available() when available != null:
return available(_that.value);case FileDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case FileDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case FileDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class FileDetailSectionDto_Available extends FileDetailSectionDto {
  const FileDetailSectionDto_Available({required final  List<FileDescriptorDto> value}): _value = value,super._();
  

 final  List<FileDescriptorDto> _value;
 List<FileDescriptorDto> get value {
  if (_value is EqualUnmodifiableListView) return _value;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_value);
}


/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileDetailSectionDto_AvailableCopyWith<FileDetailSectionDto_Available> get copyWith => _$FileDetailSectionDto_AvailableCopyWithImpl<FileDetailSectionDto_Available>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileDetailSectionDto_Available&&const DeepCollectionEquality().equals(other._value, _value));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_value));

@override
String toString() {
  return 'FileDetailSectionDto.available(value: $value)';
}


}

/// @nodoc
abstract mixin class $FileDetailSectionDto_AvailableCopyWith<$Res> implements $FileDetailSectionDtoCopyWith<$Res> {
  factory $FileDetailSectionDto_AvailableCopyWith(FileDetailSectionDto_Available value, $Res Function(FileDetailSectionDto_Available) _then) = _$FileDetailSectionDto_AvailableCopyWithImpl;
@useResult
$Res call({
 List<FileDescriptorDto> value
});




}
/// @nodoc
class _$FileDetailSectionDto_AvailableCopyWithImpl<$Res>
    implements $FileDetailSectionDto_AvailableCopyWith<$Res> {
  _$FileDetailSectionDto_AvailableCopyWithImpl(this._self, this._then);

  final FileDetailSectionDto_Available _self;
  final $Res Function(FileDetailSectionDto_Available) _then;

/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(FileDetailSectionDto_Available(
value: null == value ? _self._value : value // ignore: cast_nullable_to_non_nullable
as List<FileDescriptorDto>,
  ));
}


}

/// @nodoc


class FileDetailSectionDto_Restricted extends FileDetailSectionDto {
  const FileDetailSectionDto_Restricted({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileDetailSectionDto_RestrictedCopyWith<FileDetailSectionDto_Restricted> get copyWith => _$FileDetailSectionDto_RestrictedCopyWithImpl<FileDetailSectionDto_Restricted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileDetailSectionDto_Restricted&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'FileDetailSectionDto.restricted(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $FileDetailSectionDto_RestrictedCopyWith<$Res> implements $FileDetailSectionDtoCopyWith<$Res> {
  factory $FileDetailSectionDto_RestrictedCopyWith(FileDetailSectionDto_Restricted value, $Res Function(FileDetailSectionDto_Restricted) _then) = _$FileDetailSectionDto_RestrictedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$FileDetailSectionDto_RestrictedCopyWithImpl<$Res>
    implements $FileDetailSectionDto_RestrictedCopyWith<$Res> {
  _$FileDetailSectionDto_RestrictedCopyWithImpl(this._self, this._then);

  final FileDetailSectionDto_Restricted _self;
  final $Res Function(FileDetailSectionDto_Restricted) _then;

/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(FileDetailSectionDto_Restricted(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FileDetailSectionDto_Unsupported extends FileDetailSectionDto {
  const FileDetailSectionDto_Unsupported({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileDetailSectionDto_UnsupportedCopyWith<FileDetailSectionDto_Unsupported> get copyWith => _$FileDetailSectionDto_UnsupportedCopyWithImpl<FileDetailSectionDto_Unsupported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileDetailSectionDto_Unsupported&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'FileDetailSectionDto.unsupported(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $FileDetailSectionDto_UnsupportedCopyWith<$Res> implements $FileDetailSectionDtoCopyWith<$Res> {
  factory $FileDetailSectionDto_UnsupportedCopyWith(FileDetailSectionDto_Unsupported value, $Res Function(FileDetailSectionDto_Unsupported) _then) = _$FileDetailSectionDto_UnsupportedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$FileDetailSectionDto_UnsupportedCopyWithImpl<$Res>
    implements $FileDetailSectionDto_UnsupportedCopyWith<$Res> {
  _$FileDetailSectionDto_UnsupportedCopyWithImpl(this._self, this._then);

  final FileDetailSectionDto_Unsupported _self;
  final $Res Function(FileDetailSectionDto_Unsupported) _then;

/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(FileDetailSectionDto_Unsupported(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FileDetailSectionDto_NotFound extends FileDetailSectionDto {
  const FileDetailSectionDto_NotFound({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FileDetailSectionDto_NotFoundCopyWith<FileDetailSectionDto_NotFound> get copyWith => _$FileDetailSectionDto_NotFoundCopyWithImpl<FileDetailSectionDto_NotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FileDetailSectionDto_NotFound&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'FileDetailSectionDto.notFound(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $FileDetailSectionDto_NotFoundCopyWith<$Res> implements $FileDetailSectionDtoCopyWith<$Res> {
  factory $FileDetailSectionDto_NotFoundCopyWith(FileDetailSectionDto_NotFound value, $Res Function(FileDetailSectionDto_NotFound) _then) = _$FileDetailSectionDto_NotFoundCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$FileDetailSectionDto_NotFoundCopyWithImpl<$Res>
    implements $FileDetailSectionDto_NotFoundCopyWith<$Res> {
  _$FileDetailSectionDto_NotFoundCopyWithImpl(this._self, this._then);

  final FileDetailSectionDto_NotFound _self;
  final $Res Function(FileDetailSectionDto_NotFound) _then;

/// Create a copy of FileDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(FileDetailSectionDto_NotFound(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SecurityDetailSectionDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityDetailSectionDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SecurityDetailSectionDto()';
}


}

/// @nodoc
class $SecurityDetailSectionDtoCopyWith<$Res>  {
$SecurityDetailSectionDtoCopyWith(SecurityDetailSectionDto _, $Res Function(SecurityDetailSectionDto) __);
}


/// Adds pattern-matching-related methods to [SecurityDetailSectionDto].
extension SecurityDetailSectionDtoPatterns on SecurityDetailSectionDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SecurityDetailSectionDto_Available value)?  available,TResult Function( SecurityDetailSectionDto_Restricted value)?  restricted,TResult Function( SecurityDetailSectionDto_Unsupported value)?  unsupported,TResult Function( SecurityDetailSectionDto_NotFound value)?  notFound,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SecurityDetailSectionDto_Available() when available != null:
return available(_that);case SecurityDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case SecurityDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case SecurityDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SecurityDetailSectionDto_Available value)  available,required TResult Function( SecurityDetailSectionDto_Restricted value)  restricted,required TResult Function( SecurityDetailSectionDto_Unsupported value)  unsupported,required TResult Function( SecurityDetailSectionDto_NotFound value)  notFound,}){
final _that = this;
switch (_that) {
case SecurityDetailSectionDto_Available():
return available(_that);case SecurityDetailSectionDto_Restricted():
return restricted(_that);case SecurityDetailSectionDto_Unsupported():
return unsupported(_that);case SecurityDetailSectionDto_NotFound():
return notFound(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SecurityDetailSectionDto_Available value)?  available,TResult? Function( SecurityDetailSectionDto_Restricted value)?  restricted,TResult? Function( SecurityDetailSectionDto_Unsupported value)?  unsupported,TResult? Function( SecurityDetailSectionDto_NotFound value)?  notFound,}){
final _that = this;
switch (_that) {
case SecurityDetailSectionDto_Available() when available != null:
return available(_that);case SecurityDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case SecurityDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case SecurityDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( SecurityDetailDto value)?  available,TResult Function( String reason)?  restricted,TResult Function( String reason)?  unsupported,TResult Function( String reason)?  notFound,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SecurityDetailSectionDto_Available() when available != null:
return available(_that.value);case SecurityDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case SecurityDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case SecurityDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( SecurityDetailDto value)  available,required TResult Function( String reason)  restricted,required TResult Function( String reason)  unsupported,required TResult Function( String reason)  notFound,}) {final _that = this;
switch (_that) {
case SecurityDetailSectionDto_Available():
return available(_that.value);case SecurityDetailSectionDto_Restricted():
return restricted(_that.reason);case SecurityDetailSectionDto_Unsupported():
return unsupported(_that.reason);case SecurityDetailSectionDto_NotFound():
return notFound(_that.reason);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( SecurityDetailDto value)?  available,TResult? Function( String reason)?  restricted,TResult? Function( String reason)?  unsupported,TResult? Function( String reason)?  notFound,}) {final _that = this;
switch (_that) {
case SecurityDetailSectionDto_Available() when available != null:
return available(_that.value);case SecurityDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case SecurityDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case SecurityDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class SecurityDetailSectionDto_Available extends SecurityDetailSectionDto {
  const SecurityDetailSectionDto_Available({required this.value}): super._();
  

 final  SecurityDetailDto value;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityDetailSectionDto_AvailableCopyWith<SecurityDetailSectionDto_Available> get copyWith => _$SecurityDetailSectionDto_AvailableCopyWithImpl<SecurityDetailSectionDto_Available>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityDetailSectionDto_Available&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'SecurityDetailSectionDto.available(value: $value)';
}


}

/// @nodoc
abstract mixin class $SecurityDetailSectionDto_AvailableCopyWith<$Res> implements $SecurityDetailSectionDtoCopyWith<$Res> {
  factory $SecurityDetailSectionDto_AvailableCopyWith(SecurityDetailSectionDto_Available value, $Res Function(SecurityDetailSectionDto_Available) _then) = _$SecurityDetailSectionDto_AvailableCopyWithImpl;
@useResult
$Res call({
 SecurityDetailDto value
});




}
/// @nodoc
class _$SecurityDetailSectionDto_AvailableCopyWithImpl<$Res>
    implements $SecurityDetailSectionDto_AvailableCopyWith<$Res> {
  _$SecurityDetailSectionDto_AvailableCopyWithImpl(this._self, this._then);

  final SecurityDetailSectionDto_Available _self;
  final $Res Function(SecurityDetailSectionDto_Available) _then;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(SecurityDetailSectionDto_Available(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SecurityDetailDto,
  ));
}


}

/// @nodoc


class SecurityDetailSectionDto_Restricted extends SecurityDetailSectionDto {
  const SecurityDetailSectionDto_Restricted({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityDetailSectionDto_RestrictedCopyWith<SecurityDetailSectionDto_Restricted> get copyWith => _$SecurityDetailSectionDto_RestrictedCopyWithImpl<SecurityDetailSectionDto_Restricted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityDetailSectionDto_Restricted&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SecurityDetailSectionDto.restricted(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SecurityDetailSectionDto_RestrictedCopyWith<$Res> implements $SecurityDetailSectionDtoCopyWith<$Res> {
  factory $SecurityDetailSectionDto_RestrictedCopyWith(SecurityDetailSectionDto_Restricted value, $Res Function(SecurityDetailSectionDto_Restricted) _then) = _$SecurityDetailSectionDto_RestrictedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SecurityDetailSectionDto_RestrictedCopyWithImpl<$Res>
    implements $SecurityDetailSectionDto_RestrictedCopyWith<$Res> {
  _$SecurityDetailSectionDto_RestrictedCopyWithImpl(this._self, this._then);

  final SecurityDetailSectionDto_Restricted _self;
  final $Res Function(SecurityDetailSectionDto_Restricted) _then;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SecurityDetailSectionDto_Restricted(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityDetailSectionDto_Unsupported extends SecurityDetailSectionDto {
  const SecurityDetailSectionDto_Unsupported({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityDetailSectionDto_UnsupportedCopyWith<SecurityDetailSectionDto_Unsupported> get copyWith => _$SecurityDetailSectionDto_UnsupportedCopyWithImpl<SecurityDetailSectionDto_Unsupported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityDetailSectionDto_Unsupported&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SecurityDetailSectionDto.unsupported(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SecurityDetailSectionDto_UnsupportedCopyWith<$Res> implements $SecurityDetailSectionDtoCopyWith<$Res> {
  factory $SecurityDetailSectionDto_UnsupportedCopyWith(SecurityDetailSectionDto_Unsupported value, $Res Function(SecurityDetailSectionDto_Unsupported) _then) = _$SecurityDetailSectionDto_UnsupportedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SecurityDetailSectionDto_UnsupportedCopyWithImpl<$Res>
    implements $SecurityDetailSectionDto_UnsupportedCopyWith<$Res> {
  _$SecurityDetailSectionDto_UnsupportedCopyWithImpl(this._self, this._then);

  final SecurityDetailSectionDto_Unsupported _self;
  final $Res Function(SecurityDetailSectionDto_Unsupported) _then;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SecurityDetailSectionDto_Unsupported(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SecurityDetailSectionDto_NotFound extends SecurityDetailSectionDto {
  const SecurityDetailSectionDto_NotFound({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SecurityDetailSectionDto_NotFoundCopyWith<SecurityDetailSectionDto_NotFound> get copyWith => _$SecurityDetailSectionDto_NotFoundCopyWithImpl<SecurityDetailSectionDto_NotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SecurityDetailSectionDto_NotFound&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SecurityDetailSectionDto.notFound(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SecurityDetailSectionDto_NotFoundCopyWith<$Res> implements $SecurityDetailSectionDtoCopyWith<$Res> {
  factory $SecurityDetailSectionDto_NotFoundCopyWith(SecurityDetailSectionDto_NotFound value, $Res Function(SecurityDetailSectionDto_NotFound) _then) = _$SecurityDetailSectionDto_NotFoundCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SecurityDetailSectionDto_NotFoundCopyWithImpl<$Res>
    implements $SecurityDetailSectionDto_NotFoundCopyWith<$Res> {
  _$SecurityDetailSectionDto_NotFoundCopyWithImpl(this._self, this._then);

  final SecurityDetailSectionDto_NotFound _self;
  final $Res Function(SecurityDetailSectionDto_NotFound) _then;

/// Create a copy of SecurityDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SecurityDetailSectionDto_NotFound(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SocketDetailSectionDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SocketDetailSectionDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'SocketDetailSectionDto()';
}


}

/// @nodoc
class $SocketDetailSectionDtoCopyWith<$Res>  {
$SocketDetailSectionDtoCopyWith(SocketDetailSectionDto _, $Res Function(SocketDetailSectionDto) __);
}


/// Adds pattern-matching-related methods to [SocketDetailSectionDto].
extension SocketDetailSectionDtoPatterns on SocketDetailSectionDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SocketDetailSectionDto_Available value)?  available,TResult Function( SocketDetailSectionDto_Restricted value)?  restricted,TResult Function( SocketDetailSectionDto_Unsupported value)?  unsupported,TResult Function( SocketDetailSectionDto_NotFound value)?  notFound,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SocketDetailSectionDto_Available() when available != null:
return available(_that);case SocketDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case SocketDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case SocketDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SocketDetailSectionDto_Available value)  available,required TResult Function( SocketDetailSectionDto_Restricted value)  restricted,required TResult Function( SocketDetailSectionDto_Unsupported value)  unsupported,required TResult Function( SocketDetailSectionDto_NotFound value)  notFound,}){
final _that = this;
switch (_that) {
case SocketDetailSectionDto_Available():
return available(_that);case SocketDetailSectionDto_Restricted():
return restricted(_that);case SocketDetailSectionDto_Unsupported():
return unsupported(_that);case SocketDetailSectionDto_NotFound():
return notFound(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SocketDetailSectionDto_Available value)?  available,TResult? Function( SocketDetailSectionDto_Restricted value)?  restricted,TResult? Function( SocketDetailSectionDto_Unsupported value)?  unsupported,TResult? Function( SocketDetailSectionDto_NotFound value)?  notFound,}){
final _that = this;
switch (_that) {
case SocketDetailSectionDto_Available() when available != null:
return available(_that);case SocketDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case SocketDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case SocketDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<NetworkEndpointDto> value)?  available,TResult Function( String reason)?  restricted,TResult Function( String reason)?  unsupported,TResult Function( String reason)?  notFound,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SocketDetailSectionDto_Available() when available != null:
return available(_that.value);case SocketDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case SocketDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case SocketDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<NetworkEndpointDto> value)  available,required TResult Function( String reason)  restricted,required TResult Function( String reason)  unsupported,required TResult Function( String reason)  notFound,}) {final _that = this;
switch (_that) {
case SocketDetailSectionDto_Available():
return available(_that.value);case SocketDetailSectionDto_Restricted():
return restricted(_that.reason);case SocketDetailSectionDto_Unsupported():
return unsupported(_that.reason);case SocketDetailSectionDto_NotFound():
return notFound(_that.reason);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<NetworkEndpointDto> value)?  available,TResult? Function( String reason)?  restricted,TResult? Function( String reason)?  unsupported,TResult? Function( String reason)?  notFound,}) {final _that = this;
switch (_that) {
case SocketDetailSectionDto_Available() when available != null:
return available(_that.value);case SocketDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case SocketDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case SocketDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class SocketDetailSectionDto_Available extends SocketDetailSectionDto {
  const SocketDetailSectionDto_Available({required final  List<NetworkEndpointDto> value}): _value = value,super._();
  

 final  List<NetworkEndpointDto> _value;
 List<NetworkEndpointDto> get value {
  if (_value is EqualUnmodifiableListView) return _value;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_value);
}


/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SocketDetailSectionDto_AvailableCopyWith<SocketDetailSectionDto_Available> get copyWith => _$SocketDetailSectionDto_AvailableCopyWithImpl<SocketDetailSectionDto_Available>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SocketDetailSectionDto_Available&&const DeepCollectionEquality().equals(other._value, _value));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_value));

@override
String toString() {
  return 'SocketDetailSectionDto.available(value: $value)';
}


}

/// @nodoc
abstract mixin class $SocketDetailSectionDto_AvailableCopyWith<$Res> implements $SocketDetailSectionDtoCopyWith<$Res> {
  factory $SocketDetailSectionDto_AvailableCopyWith(SocketDetailSectionDto_Available value, $Res Function(SocketDetailSectionDto_Available) _then) = _$SocketDetailSectionDto_AvailableCopyWithImpl;
@useResult
$Res call({
 List<NetworkEndpointDto> value
});




}
/// @nodoc
class _$SocketDetailSectionDto_AvailableCopyWithImpl<$Res>
    implements $SocketDetailSectionDto_AvailableCopyWith<$Res> {
  _$SocketDetailSectionDto_AvailableCopyWithImpl(this._self, this._then);

  final SocketDetailSectionDto_Available _self;
  final $Res Function(SocketDetailSectionDto_Available) _then;

/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(SocketDetailSectionDto_Available(
value: null == value ? _self._value : value // ignore: cast_nullable_to_non_nullable
as List<NetworkEndpointDto>,
  ));
}


}

/// @nodoc


class SocketDetailSectionDto_Restricted extends SocketDetailSectionDto {
  const SocketDetailSectionDto_Restricted({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SocketDetailSectionDto_RestrictedCopyWith<SocketDetailSectionDto_Restricted> get copyWith => _$SocketDetailSectionDto_RestrictedCopyWithImpl<SocketDetailSectionDto_Restricted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SocketDetailSectionDto_Restricted&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SocketDetailSectionDto.restricted(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SocketDetailSectionDto_RestrictedCopyWith<$Res> implements $SocketDetailSectionDtoCopyWith<$Res> {
  factory $SocketDetailSectionDto_RestrictedCopyWith(SocketDetailSectionDto_Restricted value, $Res Function(SocketDetailSectionDto_Restricted) _then) = _$SocketDetailSectionDto_RestrictedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SocketDetailSectionDto_RestrictedCopyWithImpl<$Res>
    implements $SocketDetailSectionDto_RestrictedCopyWith<$Res> {
  _$SocketDetailSectionDto_RestrictedCopyWithImpl(this._self, this._then);

  final SocketDetailSectionDto_Restricted _self;
  final $Res Function(SocketDetailSectionDto_Restricted) _then;

/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SocketDetailSectionDto_Restricted(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SocketDetailSectionDto_Unsupported extends SocketDetailSectionDto {
  const SocketDetailSectionDto_Unsupported({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SocketDetailSectionDto_UnsupportedCopyWith<SocketDetailSectionDto_Unsupported> get copyWith => _$SocketDetailSectionDto_UnsupportedCopyWithImpl<SocketDetailSectionDto_Unsupported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SocketDetailSectionDto_Unsupported&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SocketDetailSectionDto.unsupported(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SocketDetailSectionDto_UnsupportedCopyWith<$Res> implements $SocketDetailSectionDtoCopyWith<$Res> {
  factory $SocketDetailSectionDto_UnsupportedCopyWith(SocketDetailSectionDto_Unsupported value, $Res Function(SocketDetailSectionDto_Unsupported) _then) = _$SocketDetailSectionDto_UnsupportedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SocketDetailSectionDto_UnsupportedCopyWithImpl<$Res>
    implements $SocketDetailSectionDto_UnsupportedCopyWith<$Res> {
  _$SocketDetailSectionDto_UnsupportedCopyWithImpl(this._self, this._then);

  final SocketDetailSectionDto_Unsupported _self;
  final $Res Function(SocketDetailSectionDto_Unsupported) _then;

/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SocketDetailSectionDto_Unsupported(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SocketDetailSectionDto_NotFound extends SocketDetailSectionDto {
  const SocketDetailSectionDto_NotFound({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SocketDetailSectionDto_NotFoundCopyWith<SocketDetailSectionDto_NotFound> get copyWith => _$SocketDetailSectionDto_NotFoundCopyWithImpl<SocketDetailSectionDto_NotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SocketDetailSectionDto_NotFound&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'SocketDetailSectionDto.notFound(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $SocketDetailSectionDto_NotFoundCopyWith<$Res> implements $SocketDetailSectionDtoCopyWith<$Res> {
  factory $SocketDetailSectionDto_NotFoundCopyWith(SocketDetailSectionDto_NotFound value, $Res Function(SocketDetailSectionDto_NotFound) _then) = _$SocketDetailSectionDto_NotFoundCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$SocketDetailSectionDto_NotFoundCopyWithImpl<$Res>
    implements $SocketDetailSectionDto_NotFoundCopyWith<$Res> {
  _$SocketDetailSectionDto_NotFoundCopyWithImpl(this._self, this._then);

  final SocketDetailSectionDto_NotFound _self;
  final $Res Function(SocketDetailSectionDto_NotFound) _then;

/// Create a copy of SocketDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(SocketDetailSectionDto_NotFound(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ThreadDetailSectionDto {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDetailSectionDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'ThreadDetailSectionDto()';
}


}

/// @nodoc
class $ThreadDetailSectionDtoCopyWith<$Res>  {
$ThreadDetailSectionDtoCopyWith(ThreadDetailSectionDto _, $Res Function(ThreadDetailSectionDto) __);
}


/// Adds pattern-matching-related methods to [ThreadDetailSectionDto].
extension ThreadDetailSectionDtoPatterns on ThreadDetailSectionDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadDetailSectionDto_Available value)?  available,TResult Function( ThreadDetailSectionDto_Restricted value)?  restricted,TResult Function( ThreadDetailSectionDto_Unsupported value)?  unsupported,TResult Function( ThreadDetailSectionDto_NotFound value)?  notFound,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadDetailSectionDto_Available() when available != null:
return available(_that);case ThreadDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case ThreadDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case ThreadDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadDetailSectionDto_Available value)  available,required TResult Function( ThreadDetailSectionDto_Restricted value)  restricted,required TResult Function( ThreadDetailSectionDto_Unsupported value)  unsupported,required TResult Function( ThreadDetailSectionDto_NotFound value)  notFound,}){
final _that = this;
switch (_that) {
case ThreadDetailSectionDto_Available():
return available(_that);case ThreadDetailSectionDto_Restricted():
return restricted(_that);case ThreadDetailSectionDto_Unsupported():
return unsupported(_that);case ThreadDetailSectionDto_NotFound():
return notFound(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadDetailSectionDto_Available value)?  available,TResult? Function( ThreadDetailSectionDto_Restricted value)?  restricted,TResult? Function( ThreadDetailSectionDto_Unsupported value)?  unsupported,TResult? Function( ThreadDetailSectionDto_NotFound value)?  notFound,}){
final _that = this;
switch (_that) {
case ThreadDetailSectionDto_Available() when available != null:
return available(_that);case ThreadDetailSectionDto_Restricted() when restricted != null:
return restricted(_that);case ThreadDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that);case ThreadDetailSectionDto_NotFound() when notFound != null:
return notFound(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ThreadInspectionDto value)?  available,TResult Function( String reason)?  restricted,TResult Function( String reason)?  unsupported,TResult Function( String reason)?  notFound,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadDetailSectionDto_Available() when available != null:
return available(_that.value);case ThreadDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case ThreadDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case ThreadDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ThreadInspectionDto value)  available,required TResult Function( String reason)  restricted,required TResult Function( String reason)  unsupported,required TResult Function( String reason)  notFound,}) {final _that = this;
switch (_that) {
case ThreadDetailSectionDto_Available():
return available(_that.value);case ThreadDetailSectionDto_Restricted():
return restricted(_that.reason);case ThreadDetailSectionDto_Unsupported():
return unsupported(_that.reason);case ThreadDetailSectionDto_NotFound():
return notFound(_that.reason);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ThreadInspectionDto value)?  available,TResult? Function( String reason)?  restricted,TResult? Function( String reason)?  unsupported,TResult? Function( String reason)?  notFound,}) {final _that = this;
switch (_that) {
case ThreadDetailSectionDto_Available() when available != null:
return available(_that.value);case ThreadDetailSectionDto_Restricted() when restricted != null:
return restricted(_that.reason);case ThreadDetailSectionDto_Unsupported() when unsupported != null:
return unsupported(_that.reason);case ThreadDetailSectionDto_NotFound() when notFound != null:
return notFound(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ThreadDetailSectionDto_Available extends ThreadDetailSectionDto {
  const ThreadDetailSectionDto_Available({required this.value}): super._();
  

 final  ThreadInspectionDto value;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDetailSectionDto_AvailableCopyWith<ThreadDetailSectionDto_Available> get copyWith => _$ThreadDetailSectionDto_AvailableCopyWithImpl<ThreadDetailSectionDto_Available>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDetailSectionDto_Available&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'ThreadDetailSectionDto.available(value: $value)';
}


}

/// @nodoc
abstract mixin class $ThreadDetailSectionDto_AvailableCopyWith<$Res> implements $ThreadDetailSectionDtoCopyWith<$Res> {
  factory $ThreadDetailSectionDto_AvailableCopyWith(ThreadDetailSectionDto_Available value, $Res Function(ThreadDetailSectionDto_Available) _then) = _$ThreadDetailSectionDto_AvailableCopyWithImpl;
@useResult
$Res call({
 ThreadInspectionDto value
});




}
/// @nodoc
class _$ThreadDetailSectionDto_AvailableCopyWithImpl<$Res>
    implements $ThreadDetailSectionDto_AvailableCopyWith<$Res> {
  _$ThreadDetailSectionDto_AvailableCopyWithImpl(this._self, this._then);

  final ThreadDetailSectionDto_Available _self;
  final $Res Function(ThreadDetailSectionDto_Available) _then;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(ThreadDetailSectionDto_Available(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadInspectionDto,
  ));
}


}

/// @nodoc


class ThreadDetailSectionDto_Restricted extends ThreadDetailSectionDto {
  const ThreadDetailSectionDto_Restricted({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDetailSectionDto_RestrictedCopyWith<ThreadDetailSectionDto_Restricted> get copyWith => _$ThreadDetailSectionDto_RestrictedCopyWithImpl<ThreadDetailSectionDto_Restricted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDetailSectionDto_Restricted&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'ThreadDetailSectionDto.restricted(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ThreadDetailSectionDto_RestrictedCopyWith<$Res> implements $ThreadDetailSectionDtoCopyWith<$Res> {
  factory $ThreadDetailSectionDto_RestrictedCopyWith(ThreadDetailSectionDto_Restricted value, $Res Function(ThreadDetailSectionDto_Restricted) _then) = _$ThreadDetailSectionDto_RestrictedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ThreadDetailSectionDto_RestrictedCopyWithImpl<$Res>
    implements $ThreadDetailSectionDto_RestrictedCopyWith<$Res> {
  _$ThreadDetailSectionDto_RestrictedCopyWithImpl(this._self, this._then);

  final ThreadDetailSectionDto_Restricted _self;
  final $Res Function(ThreadDetailSectionDto_Restricted) _then;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ThreadDetailSectionDto_Restricted(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ThreadDetailSectionDto_Unsupported extends ThreadDetailSectionDto {
  const ThreadDetailSectionDto_Unsupported({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDetailSectionDto_UnsupportedCopyWith<ThreadDetailSectionDto_Unsupported> get copyWith => _$ThreadDetailSectionDto_UnsupportedCopyWithImpl<ThreadDetailSectionDto_Unsupported>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDetailSectionDto_Unsupported&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'ThreadDetailSectionDto.unsupported(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ThreadDetailSectionDto_UnsupportedCopyWith<$Res> implements $ThreadDetailSectionDtoCopyWith<$Res> {
  factory $ThreadDetailSectionDto_UnsupportedCopyWith(ThreadDetailSectionDto_Unsupported value, $Res Function(ThreadDetailSectionDto_Unsupported) _then) = _$ThreadDetailSectionDto_UnsupportedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ThreadDetailSectionDto_UnsupportedCopyWithImpl<$Res>
    implements $ThreadDetailSectionDto_UnsupportedCopyWith<$Res> {
  _$ThreadDetailSectionDto_UnsupportedCopyWithImpl(this._self, this._then);

  final ThreadDetailSectionDto_Unsupported _self;
  final $Res Function(ThreadDetailSectionDto_Unsupported) _then;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ThreadDetailSectionDto_Unsupported(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ThreadDetailSectionDto_NotFound extends ThreadDetailSectionDto {
  const ThreadDetailSectionDto_NotFound({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDetailSectionDto_NotFoundCopyWith<ThreadDetailSectionDto_NotFound> get copyWith => _$ThreadDetailSectionDto_NotFoundCopyWithImpl<ThreadDetailSectionDto_NotFound>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDetailSectionDto_NotFound&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'ThreadDetailSectionDto.notFound(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ThreadDetailSectionDto_NotFoundCopyWith<$Res> implements $ThreadDetailSectionDtoCopyWith<$Res> {
  factory $ThreadDetailSectionDto_NotFoundCopyWith(ThreadDetailSectionDto_NotFound value, $Res Function(ThreadDetailSectionDto_NotFound) _then) = _$ThreadDetailSectionDto_NotFoundCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$ThreadDetailSectionDto_NotFoundCopyWithImpl<$Res>
    implements $ThreadDetailSectionDto_NotFoundCopyWith<$Res> {
  _$ThreadDetailSectionDto_NotFoundCopyWithImpl(this._self, this._then);

  final ThreadDetailSectionDto_NotFound _self;
  final $Res Function(ThreadDetailSectionDto_NotFound) _then;

/// Create a copy of ThreadDetailSectionDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ThreadDetailSectionDto_NotFound(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
