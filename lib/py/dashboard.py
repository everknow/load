import matplotlib.pyplot as plt
import matplotlib.animation as animation
import requests


fig, ax = plt.subplots(1,2)

x = []
submitted_partial = []
submitted = []
processed_partial = []
processed = []
l1, = ax[0].plot(x, submitted)
l2, = ax[0].plot(x, processed)
l3, = ax[1].plot(x, submitted_partial)
l4, = ax[1].plot(x, processed_partial)

def animate(_):
    response = requests.get('http://localhost:8888/stats')
    if response.status_code == 200:
        data = response.json()
        submitted_partial.append((data['submitted']['succeeded'] - submitted[-1]) if len(submitted) else 0)
        submitted.append(data['submitted']['succeeded'])
        processed_partial.append((data['processed']['succeeded'] - processed[-1]) if len(processed) else 0)
        processed.append(data['processed']['succeeded'])
        x.append(len(x) + 1)
        l1.set_data(x, submitted)
        l2.set_data(x, processed)
        l3.set_data(x, submitted_partial)
        l4.set_data(x, processed_partial)
        ax[0].set_xlim(1, len(x))
        ax[0].set_ylim(min(submitted)-5, max(submitted)+5)
        ax[1].set_xlim(1, len(x))
        ax[1].set_ylim(min(submitted_partial)-0.3, max(submitted_partial+processed_partial)+0.3)
    return [l1, l2, l3, l4]

ani = animation.FuncAnimation(fig, animate, interval=5000)
plt.show()