# Disable debug packages — we're repackaging precompiled upstream binaries
%global debug_package %{nil}
%undefine __brp_check_rpaths

# Exclude private shared libraries bundled inside the application directory
%global __provides_exclude_from ^/opt/android-studio/.*\.so.*$
%global __requires_exclude_from ^/opt/android-studio/.*\.so.*$
%global __requires_exclude ^(libstdc\+\+\.so\.6.*|libgcc_s\.so\.1.*|/usr/bin/python3)

Name:           android-studio
Version:        2026.1.1.10
Release:        1%{?dist}
Summary:        The official IDE for Android development

License:        Proprietary (Android Studio Terms of Service)
URL:            https://developer.android.com/studio
ExclusiveArch:  x86_64

# Android Studio only ships a single Linux x86_64 archive (no ARM64 build available)
Source0:        https://dl.google.com/dl/android/studio/ide-zips/%{version}/android-studio-quail1-patch2-linux.tar.gz
Source1:        android-studio.desktop

BuildRequires:  tar
BuildRequires:  gzip

Requires:       liberation-fonts
Requires:       libX11
Requires:       libXext
Requires:       libXrender
Requires:       libXtst
Requires:       libXi
Requires:       freetype
Requires:       fontconfig

%description
Android Studio is the official integrated development environment (IDE)
for Android app development, based on IntelliJ IDEA. It provides a
fast, feature-rich environment for building apps for every Android device.

This package repackages the upstream precompiled binaries for Fedora.

%prep
%setup -c -T
tar -xzf %{SOURCE0}
# The archive extracts to a directory named "android-studio"

%build
# No build steps needed — repackaging precompiled upstream binaries

%install
mkdir -p %{buildroot}/opt
mv android-studio %{buildroot}/opt/android-studio

# Write version metadata
echo "%{version}" > %{buildroot}/opt/android-studio/version.txt

# Ensure launch script is executable
chmod +x %{buildroot}/opt/android-studio/bin/studio.sh

# Create a thin wrapper in /usr/bin so users can run "android-studio" directly
mkdir -p %{buildroot}%{_bindir}
printf '#!/usr/bin/env bash\nexec /opt/android-studio/bin/studio.sh "$@"\n' \
    > %{buildroot}%{_bindir}/android-studio
chmod +x %{buildroot}%{_bindir}/android-studio

# Install desktop entry
mkdir -p %{buildroot}%{_datadir}/applications
install -m 644 %{SOURCE1} %{buildroot}%{_datadir}/applications/android-studio.desktop

# Install icon (taken from the archive itself at install time via trigger)
mkdir -p %{buildroot}%{_datadir}/icons/hicolor/128x128/apps
install -m 644 %{buildroot}/opt/android-studio/bin/studio.png \
    %{buildroot}%{_datadir}/icons/hicolor/128x128/apps/android-studio.png || true

mkdir -p %{buildroot}%{_datadir}/pixmaps
install -m 644 %{buildroot}/opt/android-studio/bin/studio.png \
    %{buildroot}%{_datadir}/pixmaps/android-studio.png || true

%post
/usr/bin/update-desktop-database &>/dev/null || :
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || :

%postun
/usr/bin/update-desktop-database &>/dev/null || :
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor &>/dev/null || :

%files
/opt/android-studio/
%{_bindir}/android-studio
%{_datadir}/applications/android-studio.desktop
%{_datadir}/icons/hicolor/128x128/apps/android-studio.png
%{_datadir}/pixmaps/android-studio.png

%changelog
* Mon Jul 07 2026 Aditya <adityas@example.com> - 2026.1.1.10-1
- Initial RPM packaging of Android Studio Quail 1 Patch 2 (2026.1.1.10) for Fedora
