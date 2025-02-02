//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation
import UIKit
import avs
import WireSyncEngine

protocol AVSIdentifierProvider {
    var stream: Stream { get }
}

extension AVSVideoView: AVSIdentifierProvider {
    
    var stream: Stream {
        return Stream(
            streamId: AVSClient(userId: UUID(uuidString: userid)!, clientId: clientid),
            participantName: nil,
            microphoneState: .unmuted,
            videoState: .none,
            isParticipantActiveSpeaker: false
        )
    }
}

private extension Stream {
    var isParticipantUnmutedAndActiveSpeaker: Bool {
        return isParticipantActiveSpeaker && microphoneState == .unmuted
    }
}

class BaseVideoPreviewView: OrientableView, AVSIdentifierProvider {

    var stream: Stream {
        didSet {
            updateUserDetails()
            updateBorderVisibility()
        }
    }
    
    var isMaximized: Bool = false
    
    private var delta: OrientationDelta = OrientationDelta()
    private var detailsConstraints: UserDetailsConstraints?
    private var isCovered: Bool
    
    private var adjustedInsets: UIEdgeInsets {
        safeAreaInsetsOrFallback.adjusted(for: delta)
    }
    
    private var userDetailsAlpha: CGFloat {
        isCovered ? 0 : 1
    }
    
    let userDetailsView = VideoParticipantDetailsView()
    
    init(stream: Stream, isCovered: Bool) {
        self.stream = stream
        self.isCovered = isCovered
        
        super.init(frame: .zero)

        setupViews()
        createConstraints()
        updateUserDetails()
        updateBorderVisibility()
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateUserDetailsVisibility), name: .videoGridVisibilityChanged, object: nil)
    }
    
    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    func updateUserDetails() {
        userDetailsView.name = stream.participantName
        userDetailsView.microphoneIconStyle = MicrophoneIconStyle(state: stream.microphoneState, shouldPulse: stream.isParticipantActiveSpeaker)
        userDetailsView.alpha = userDetailsAlpha
    }
    
    func setupViews() {
        layer.borderColor = UIColor.accent().cgColor
        layer.borderWidth = 0
        backgroundColor = .graphite
        userDetailsView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(userDetailsView)
        userDetailsView.alpha = 0.0
    }
    
    func createConstraints() {
        detailsConstraints = UserDetailsConstraints(
            view: userDetailsView,
            superview: self,
            safeAreaInsets: adjustedInsets
        )
       
        NSLayoutConstraint.activate([userDetailsView.heightAnchor.constraint(equalToConstant: 24)])
    }

    // MARK: - Frame Border
    
    private let isActiveSpeakerFrameEnabled = false
    
    private func updateBorderVisibility() {
        guard isActiveSpeakerFrameEnabled else { return }
        layer.borderWidth = stream.isParticipantUnmutedAndActiveSpeaker ? 1 : 0
    }
    
    // MARK: - Orientation & Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        detailsConstraints?.updateEdges(with: adjustedInsets)
    }
    
    func layout(forInterfaceOrientation interfaceOrientation: UIInterfaceOrientation,
                deviceOrientation: UIDeviceOrientation)
    {
        guard let superview = superview else { return }
        
        delta = OrientationDelta(interfaceOrientation: interfaceOrientation,
                                 deviceOrientation: deviceOrientation)
        
        transform = CGAffineTransform(rotationAngle: delta.radians)
        frame = superview.bounds
        
        layoutSubviews()
    }
        
    // MARK: - Visibility
    @objc private func updateUserDetailsVisibility(_ notification: Notification?) {
        guard let isCovered = notification?.userInfo?[VideoGridViewController.isCoveredKey] as? Bool else {
            return
        }
        self.isCovered = isCovered
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.userDetailsView.alpha = self.userDetailsAlpha
        })
    }
    
    // MARK: - Accessibility for automation
    override var accessibilityIdentifier: String? {
        get {
            let name = stream.participantName ?? ""
            let maximizationState = isMaximized ? "maximized" : "minimized"
            let activityState = stream.isParticipantUnmutedAndActiveSpeaker ? "active" : "inactive"
            return "VideoView.\(name).\(maximizationState).\(activityState)"
        }
        set {}
    }
}

// MARK: - User Details Constraints
private struct UserDetailsConstraints {
    private let bottom: NSLayoutConstraint
    private let leading: NSLayoutConstraint
    private let trailing: NSLayoutConstraint
    
    private let margin: CGFloat = 8
    
    init(view: UIView, superview: UIView, safeAreaInsets insets: UIEdgeInsets) {
        bottom = view.bottomAnchor.constraint(equalTo: superview.bottomAnchor)
        leading = view.leadingAnchor.constraint(equalTo: superview.leadingAnchor)
        trailing = view.trailingAnchor.constraint(lessThanOrEqualTo: superview.trailingAnchor)
        updateEdges(with: insets)
        NSLayoutConstraint.activate([bottom, leading, trailing])
    }
    
    func updateEdges(with insets: UIEdgeInsets) {
        leading.constant = margin + insets.left
        trailing.constant = -(margin + insets.right)
        bottom.constant = -(margin + insets.bottom)
    }
}
