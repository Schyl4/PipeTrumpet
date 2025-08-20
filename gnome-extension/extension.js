import GObject from 'gi://GObject';
import St from 'gi://St';
import GLib from 'gi://GLib';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as Slider from 'resource:///org/gnome/shell/ui/slider.js';

function execCommand(command) {
    try {
        let [success, stdout, stderr, status] = GLib.spawn_command_line_sync(command);
        if (!success || status !== 0) {
            return null;
        }
        return new TextDecoder().decode(stdout);
    } catch (e) {
        return null;
    }
}

const SoundButton = GObject.registerClass(
class SoundButton extends PanelMenu.Button {
    _init() {
        super._init(0.0);
        
        this.add_child(new St.Icon({
            icon_name: 'audio-volume-high-symbolic',
            style_class: 'system-status-icon'
        }));
        
        this._headerItem = new PopupMenu.PopupMenuItem('Audio Mixer Controls');
        this._headerItem.setSensitive(false);
        this._headerItem.style_class = 'header-item';
        this.menu.addMenuItem(this._headerItem);
        
        this.menu.connect('open-state-changed', (menu, isOpen) => {
            if (isOpen) {
                this._refreshMenu();
            }
        });
    }
    
    _refreshMenu() {
        this.menu.removeAll();
        
        this._headerItem = new PopupMenu.PopupMenuItem('Audio Mixer Controls');
        this._headerItem.setSensitive(false);
        this._headerItem.style_class = 'header-item hidden-header';
        this.menu.addMenuItem(this._headerItem);
        
        const sinks = this._findSinks();
        
        if (sinks.length === 0) {
            this.menu.addMenuItem(new PopupMenu.PopupMenuItem('No AudioMixer sinks found', {
                reactive: false,
                style_class: 'no-sinks-message'
            }));
            return;
        }
        
        for (let i = 0; i < sinks.length; i++) {
            this._addSinkWithVolume(sinks[i]);
        }
    }
    
    _addSinkWithVolume(sink) {
        const nameItem = new PopupMenu.PopupBaseMenuItem({
            reactive: false,
            style_class: 'sink-name-item'
        });
        
        const nameLayout = new St.BoxLayout({
            vertical: false,
            x_expand: true
        });
        
        const nameLabel = new St.Label({
            text: sink.name,
            style_class: 'sink-name-label',
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER
        });
        
        const volumeLabel = new St.Label({
            text: `${Math.round(sink.volume * 100)}%`,
            style_class: 'volume-percentage',
            x_align: Clutter.ActorAlign.END,
            y_align: Clutter.ActorAlign.CENTER
        });
        
        nameLayout.add_child(nameLabel);
        nameLayout.add_child(volumeLabel);
        nameItem.add_child(nameLayout);
        this.menu.addMenuItem(nameItem);
        
        const sliderItem = new PopupMenu.PopupBaseMenuItem({
            activate: false,
            style_class: 'minimal-slider-item'
        });
        
        const slider = new Slider.Slider(sink.volume);
        
        slider.connect('notify::value', () => {
            const value = slider.value;
            const percent = Math.round(value * 100);
            
            volumeLabel.set_text(`${percent}%`);
            
            GLib.spawn_command_line_async(`wpctl set-volume ${sink.id} ${percent}%`);
        });
        
        sliderItem.add_child(slider);
        
        this.menu.addMenuItem(sliderItem);
    }
    
    _findSinks() {
        const sinks = [];
        
        const output = execCommand('pw-cli list-objects Node');
        if (!output) {
            return sinks;
        }
        
        const nodeRegex = /id\s+(\d+),\s+type\s+PipeWire:Interface:Node\/\d+([^]*?)(?=id\s+\d+,\s+type|$)/g;
        let match;
        
        while ((match = nodeRegex.exec(output)) !== null) {
            const nodeId = match[1];
            const content = match[2];
            
            if (content.includes('node.name = "AudioMixer-')) {
                const nameMatch = content.match(/node\.name\s+=\s+"AudioMixer-([^"]+)"/);
                if (nameMatch) {
                    const name = nameMatch[1];
                    
                    let volume = 0.75;
                    const volOutput = execCommand(`wpctl get-volume ${nodeId}`);
                    if (volOutput) {
                        const volMatch = volOutput.match(/Volume: ([0-9.]+)/);
                        if (volMatch) {
                            volume = parseFloat(volMatch[1]);
                        }
                    }
                    
                    sinks.push({
                        id: nodeId,
                        name: name,
                        volume: volume
                    });
                }
            }
        }
        
        return sinks;
    }
});

export default class PipeTrumpet extends Extension {
    enable() {
        this._indicator = new SoundButton();
        Main.panel.addToStatusArea('sound-control', this._indicator);
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}